# variables.tf - Definición de variables para la infraestructura

variable "prefix" {
  description = "Prefijo para todos los recursos"
  default     = "nodejs-api"
}

variable "resource_group_name" {
  description = "Nombre del grupo de recursos"
  default     = "nodejs-api-rg"
}

variable "location" {
  description = "Ubicación de Azure para los recursos"
  default     = "eastus"
}

variable "controller_ip" {
  description = "Dirección IP de la máquina controladora (desde donde se ejecuta Terraform/Ansible)"
  type        = string
}

variable "vm_admin_username" {
  description = "Nombre de usuario administrador para la VM"
  default     = "azureuser"
}

variable "ssh_public_key_path" {
  description = "Ruta al archivo de clave pública SSH"
  default     = "~/.ssh/id_rsa.pub"
}

variable "ssh_private_key_path" {
  description = "Ruta al archivo de clave privada SSH"
  default     = "~/.ssh/id_rsa"
}

variable "mysql_user" {
  description = "Usuario de MySQL"
  default     = "admin"
}

variable "mysql_password" {
  description = "Contraseña de MySQL"
  sensitive   = true
}

variable "mysql_database" {
  description = "Nombre de la base de datos MySQL"
  default     = "testdb"
}
