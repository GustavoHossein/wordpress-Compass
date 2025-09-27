#!/bin/bash

# Variáveis
EFS_FILE_SYSTEM_ID="fs-03e1567765f76a7de"
DB_HOST="wordpress-rds.ckvsyqyiw830.us-east-1.rds.amazonaws.com"
DB_NAME="wordpress"
DB_USER="admin"
DB_PASSWORD="GustavoPB2025"
PROJECT_DIR="/home/ec2-user/wordpress"
EFS_MOUNT_DIR="/mnt/efs"

# Atualizações e instalação do Docker
yum update -y
yum install -y docker

# Inicia o serviço docker
service docker start
usermod -a -G docker ec2-user

# Instala Docker Compose (versão atual recomendada)
curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Instala EFS utils e monta o sistema
yum install -y amazon-efs-utils
mkdir -p ${EFS_MOUNT_DIR}
mount -t efs ${EFS_FILE_SYSTEM_ID}:/ ${EFS_MOUNT_DIR}
echo "${EFS_FILE_SYSTEM_ID}:/ ${EFS_MOUNT_DIR} efs defaults,_netdev 0 0" >> /etc/fstab

# Permissões para o EFS
mkdir -p ${EFS_MOUNT_DIR}/html
chown -R 33:33 ${EFS_MOUNT_DIR}/html
chmod -R 775 ${EFS_MOUNT_DIR}/html

# Prepara o projeto WordPress
mkdir -p ${PROJECT_DIR}
cd ${PROJECT_DIR}

# Cria docker-compose.yml
cat > docker-compose.yml <<EOL
version: '3.7'
services:
  wordpress:
    image: wordpress:latest
    container_name: wordpress
    environment:
      WORDPRESS_DB_HOST: ${DB_HOST}
      WORDPRESS_DB_NAME: ${DB_NAME}
      WORDPRESS_DB_USER: ${DB_USER}
      WORDPRESS_DB_PASSWORD: ${DB_PASSWORD}
    ports:
      - 80:80
    volumes:
      - ${EFS_MOUNT_DIR}/html:/var/www/html
EOL

# Inicia o container
docker-compose up -d