#!/bin/bash

# Initialize Terraform
terraform init

# Apply Terraform configuration
terraform apply -auto-approve

# Get MySQL VM public IP
MYSQL_IP=$(terraform output -raw mysql_vm_public_ip)

# Create Ansible inventory file
echo "[mysql_vm]" > inventory.ini
echo "$MYSQL_IP ansible_user=adminuser" >> inventory.ini

# Configure MySQL with Ansible
ansible-playbook -i inventory.ini mysql_setup.yml --private-key ~/.ssh/id_rsa

# Get App Service name
APP_SERVICE_NAME=$(terraform output -raw app_service_name)

# Configure App Service settings
az webapp config appsettings set \
  --name $APP_SERVICE_NAME \
  --resource-group nodejs-mysql-rg \
  --settings \
    DB_HOST=$MYSQL_IP \
    DB_USER=nodejs_user \
    DB_PASSWORD=UserPassword123! \
    DB_NAME=nodejs_db

# Deploy Node.js application
cd nodejs-express-mysql
az webapp deployment source config-zip \
  --name $APP_SERVICE_NAME \
  --resource-group nodejs-mysql-rg \
  --src ./app.zip
