#!/bin/sh

VPC_NAME=wordpress-vpc
SUBNET_NAME=wordpress-subnet
SUBNET_CIDR=10.10.10.0/24

INTERNAL_FIREWALL_RULE=wordpress-manage-firewall-rule
EXTERNAL_FIREWALL_RULE=wordpress-firewall-rule

SERVER_HOSTNAME=wordpress

SERVER_INTERNAL_IP=wordpress
SERVER_INTERNAL_ADDRESS=10.10.10.11

REGION=us-west1
ZONE=us-west1-a
OFFICE_IP=118.163.16.148

# Create VPC
gcloud compute networks create $VPC_NAME --subnet-mode custom

# Create subnet
gcloud compute networks subnets create $SUBNET_NAME \
	--network $VPC_NAME \
	--range $SUBNET_CIDR \
    --region $REGION

# Create firewall rule
gcloud compute firewall-rules create $EXTERNAL_FIREWALL_RULE --direction=INGRESS --priority=65533 --network=$VPC_NAME --action=ALLOW --rules=tcp:8000 --source-ranges="0.0.0.0/0"
gcloud compute firewall-rules create $INTERNAL_FIREWALL_RULE --direction=INGRESS --priority=65534 --network=$VPC_NAME --action=ALLOW --rules=tcp:22,icmp --source-ranges=$OFFICE_IP

# Create Static Internal IP
gcloud compute addresses create $SERVER_INTERNAL_IP --addresses=$SERVER_INTERNAL_ADDRESS --region=$REGION --subnet=$SUBNET_NAME

# Create Server
gcloud compute instances create $SERVER_HOSTNAME \
  --async \
  --boot-disk-size 30GB \
  --can-ip-forward \
  --image-family ubuntu-2204-lts \
  --image-project ubuntu-os-cloud \
  --machine-type e2-micro \
  --private-network-ip $SERVER_INTERNAL_ADDRESS \
  --scopes compute-rw,storage-ro,service-management,service-control,logging-write,monitoring \
  --subnet $SUBNET_NAME \
  --zone $ZONE \
  --tags $VPC_NAME,$SERVER_HOSTNAME \
  --metadata=startup-script='#!/bin/bash

apt-get update
apt-get remove vim vim-runtime vim-tiny vim-common vim-scripts vim-doc -y
apt-get install vim -y

apt update
apt install -y apt-transport-https curl

apt-get update
apt-get install ca-certificates curl -y
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update

apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

NEW_USER=adlerhu
useradd -m $NEW_USER
chsh -s /bin/bash $NEW_USER
usermod -aG sudo $NEW_USER
mkdir /home/$NEW_USER/.ssh/
touch /home/$NEW_USER/.ssh/authorized_keys
chown -R $NEW_USER:$NEW_USER /home/$NEW_USER/.ssh/

touch /etc/sudoers.d/$NEW_USER
chmod 440 /etc/sudoers.d/$NEW_USER
echo "$NEW_USER ALL=(ALL:ALL) NOPASSWD:ALL" | sudo tee -a /etc/sudoers.d/$NEW_USER

userdel ubuntu
rm -rf /home/ubuntu

docker volume create mysql
docekr volume create wordpress

usermod -aG docker adlerhu
mkdir /home/adlerhu/wordpress/
git clone https://github.com/AdlerHu/wordpress.git /home/adlerhu/wordpress/
chown -R adlerhu:adlerhu /home/adlerhu/wordpress/'
