# Arquitetura de Alta Disponibilidade para WordPress na AWS

<img src="Images/diagrama.jpeg" alt="Diagrama da Infraestrutura" style="display: block; margin: 0 auto;">

## 📌 Introduction
Este projeto demonstra a implantação de uma **arquitetura escalável e altamente disponível** para hospedar um site WordPress na **AWS**.  
A infraestrutura utiliza recursos gerenciados como **EC2, RDS, EFS, Auto Scaling Group (ASG)** e **Application Load Balancer (ALB)**, todos dentro de uma **VPC customizada** com sub-redes públicas e privadas.  

---

## 🏗️ Architectural Overview
- **VPC customizada** com 2 sub-redes públicas e 2 privadas  
- **Internet Gateway** para saída de internet das sub-redes públicas  
- **NAT Gateway** para permitir saída de internet das sub-redes privadas
- **Security Groups** com regras restritivas, permitindo apenas comunicação essencial entre os serviços
- **Amazon RDS (MySQL)** para banco de dados gerenciado e seguro  
- **Amazon EFS** para armazenamento compartilhado dos arquivos de mídia 
- **Instâncias EC2** em containers Docker com **docker-compose**
- **Application Load Balancer (ALB)** para distribuir o tráfego entre múltiplas zonas de disponibilidade
- **Auto Scaling Group (ASG)** para ajustar automaticamente a capacidade conforme a demanda

---

## ⚙️ Steps to Creation

### 1.1 Create VPC with subnets and NAT Gateway automatically

- Acesse o console da AWS > **VPC > Your VPCs > Create VPC**
- Selecione: ✅ **VPC and more**
- **Auto-generate**: ✅
- **Name**: `wordpress`
- **IPv4 CIDR block**: `10.0.0.0/16`
- **IPv6 CIDR block**: No IPv6
- **Tenancy**: Default
- **Number of Availability Zones (AZs)**: `2`
- **Number of public subnets**: `2`
- **Number of private subnets**: `2`
- **Gateways NAT**: selecione **1 per AZ** (um para cada AZ)
- **VPC endpoints**: None
- **Create VPC**

---

### 1.2 Create Security Groups (EC2, RDS, EFS, and LB)
- Acesse o console da AWS > **EC2 > Network & Security > Security Groups > Create security groups**

| **Security Group** | **Inbound (entradas)** | **Outbound (saídas)** | **Propósito / Observações** |
|--------------------|-------------------------|------------------------|------------------------------|
|**EC2-SG** | - SSH **22** — origem: **Seu-IP** *(Teste)* <br> - HTTP **80** — origem: **SG-ALB** <br> - NFS **2049** — origem: **EFS-SG** | - All traffic → `0.0.0.0/0` | Instâncias privadas rodando WordPress/Docker. |
|**RDS-SG** | - MySQL **3306** — origem: **SG-EC2** | - MySQL **3306** — origem: **SG-EC2** | Comunicação bidirecional com EC2. |
|**EFS-SG** | - NFS **2049** — origem: **SG-EC2** | - NFS **2049** — origem: **SG-EC2** | Comunicação bidirecional |
|**ALB-SG** | - HTTP **80** — `0.0.0.0/0` | - HTTP **80** — `0.0.0.0/0` | Redirecionar tráfego para instâncias |

---

### 1.3 – Create Database (RDS)

- Acesse o console da AWS > **RDS > Databases > Create database**
- **Choose a database creation method**: `Standard Create`
- **Engine options**: `MySQL`
- **Templates**: `Free Tier`
- **DB instance identifier**: `wordpress-rds`
- **Master username**: `admin`
- **Credentials management**: `Self managed`
- **Master password**: `Strong password`
- **Instance configuration**: `db.t3.micro`
- **Virtual private cloud (VPC)**: `wordpress-vpc`
- **Public access**: `No`
- **Existing VPC security groups**: `rds-sg`
- **Database port**: `3306`
- ✅ **Create database**

---

### 1.4 Create File System (EFS)

- Acesse o console da AWS > **EFS > Create file system > Customize**
- **Name**: `wordpress-efs`
- **File system type**: `Regional`
- **Automatic backups**: ❌ `uncheck`
- **Lifecycle management**: `All None`
- **Network access**: `Your VPC`
- **Private subnets**:
  - `wordpress-subnet-private1-us-east-1a`
  - `wordpress-subnet-private2-us-east-1b`
- **Click**: `Next two times`
- ✅ **Create**

---

### 1.5 Create Launch Template (EC2)

- Acesse o console da AWS > **EC2 > Instances > Launch Template**
- **Launch template name**: `wordpress-template`
- **Description**: `Template de inicializacao`
- **Auto Scaling guidance**: ✅ `check`
- **Application and OS Images (Amazon Machine Image)**:
  - **Quick Start**: `Amazon Linux`
- **Instance type**: `t2.micro`
- **Key pair (login)**: `Your Key`(optional)
- **Network settings**:
  - **Subnet**: `Don't include in launch template`
  - **Availability Zone**: `Don't include in launch template`
- **Select existing security group**: `EC2-SG`
- **Resource tags**: `Your tags`
- **Advanced details**: `Paste Script > User data`
- ✅ **Create**

### ❗Important❗
  - Change variables

```bash
#!/bin/bash

# Variáveis
EFS_FILE_SYSTEM_ID="seu_id_efs"
DB_HOST="seu_endpoint_rds"
DB_NAME="seu_nome_bd"
DB_USER="seu_usuario_bd"
DB_PASSWORD="sua_senha_bd"
PROJECT_DIR="/home/ec2-user/wordpress" # Não Mudar
EFS_MOUNT_DIR="/mnt/efs" # Não Mudar

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

```

---

### 1.6 Create Target Group (TG)

- Acesse o console da AWS > **EC2 > Target groups > Create target group**
- **Choose a target type**: `Instances`
- **Target group name**: `wordpress-tg`
- **VPC**: ✅ `wordpress-vpc`
- ✅ **Create**

---

### 1.7 Create Load Balancer (LB)

- Acesse o console da AWS > **EC2 > Load Balancers > Create Load Balancer**
- **Choose**: `Application Load Balancer`
- **Click**: `Create`
- **Load balancer name**: ✅ `wordpress-alb`
- **Scheme**: `Internet-facing`
- **Network mapping**:
  - **VPC**: `wordpress-vpc`
  - **Availability Zones and subnets**: **sub-rede pública**
    - `wordpress-subnet-public1-us-east-1a`
    - `wordpress-subnet-public2-us-east-1b`
- **Security groups**: `LB-SG`
- **Listeners and routing**:
  - **Protocol**: `HTTP`
  - **Port**: `80`
  - **Target Group**: `wordpress-tg`
- ✅ **Create**

---

### 1.8 Create Auto Scalling Group (ASG)

- Acesse o console da AWS > **EC2 > Auto Scalling Group > Create Auto Scalling Group**
- **Name**: `wordpress-asg`
- **Launch Template**: `wordpress-template`
- **Version**: ✅ `Default(1)`
- **VPC**: `wordpress-vpc`
- **Subnets**: `Select 2 subnets **Privates**`
- **Balancing option**: `Best balanced effort`
- **Associate with load balancer**:
  - **Select the target group**: `wordpress-tg`
- **Health checks**:
  - **Check**: `Enable Elastic Load Balancing health checks`
- **Desired capacity**:
  - **Desired**: `2`
  - **Minimum**: `2`
  - **Maximum**: `4`
- **Monitoring (CloudWatch)**:
  - **Check**: `Enable metric collection in CloudWatch`
- ✅ **Create**

---

### 💡 Design Tests
During this phase, tests were conducted to verify the full functionality of the WordPress application deployed on the AWS infrastructure. The results confirmed that all components are properly integrated and operating as expected.

- 1️⃣ The application was successfully accessed via a browser, using the Application Load Balancer's public DNS to load the WordPress installer.
  
<img src="Images/" alt="Imagem navegador" style="display: block; margin: 0 auto;">

- 2️⃣ Alterarrrrrrrrrrrrrrrrrr
  
<img src="Images/" alt="Web post" style="display: block; margin: 0 auto;">

---

### 📋 Project completion

The implementation of this infrastructure on AWS successfully demonstrated the creation of a production environment for WordPress, meeting the requirements for high availability, security, and scalability. The proposed architecture was operationally validated through successful access to the WordPress installer via an Application Load Balancer, confirming the correct configuration of all interconnected components.
























