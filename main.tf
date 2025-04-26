# main.tf - Configuración principal de Terraform para la infraestructura

# Configuración del proveedor de Azure
provider "azurerm" {
  features {}
}

# Grupo de recursos para todos los componentes
resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
}

# Red virtual para aislar los componentes
resource "azurerm_virtual_network" "vnet" {
  name                = "${var.prefix}-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# Subred para la VM de MySQL
resource "azurerm_subnet" "db_subnet" {
  name                 = "${var.prefix}-db-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Subred para App Service
resource "azurerm_subnet" "app_subnet" {
  name                 = "${var.prefix}-app-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.2.0/24"]
  
  delegation {
    name = "app-service-delegation"
    
    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

# IP pública para la VM de MySQL (sólo para gestión)
resource "azurerm_public_ip" "mysql_public_ip" {
  name                = "${var.prefix}-mysql-public-ip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# Grupo de seguridad de red para MySQL
resource "azurerm_network_security_group" "mysql_nsg" {
  name                = "${var.prefix}-mysql-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  # Regla para permitir SSH solo desde la máquina controladora
  security_rule {
    name                       = "SSH"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.controller_ip
    destination_address_prefix = "*"
  }

  # Regla para permitir MySQL solo desde la subred de App Service
  security_rule {
    name                       = "MySQL"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3306"
    source_address_prefix      = azurerm_subnet.app_subnet.address_prefixes[0]
    destination_address_prefix = "*"
  }
}

# Interfaz de red para MySQL VM
resource "azurerm_network_interface" "mysql_nic" {
  name                = "${var.prefix}-mysql-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.db_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.mysql_public_ip.id
  }
}

# Asociar el NSG a la interfaz de red
resource "azurerm_network_interface_security_group_association" "mysql_nsg_assoc" {
  network_interface_id      = azurerm_network_interface.mysql_nic.id
  network_security_group_id = azurerm_network_security_group.mysql_nsg.id
}

# Máquina virtual para MySQL
resource "azurerm_linux_virtual_machine" "mysql_vm" {
  name                  = "${var.prefix}-mysql-vm"
  location              = azurerm_resource_group.rg.location
  resource_group_name   = azurerm_resource_group.rg.name
  size                  = "Standard_B2s"
  admin_username        = var.vm_admin_username
  network_interface_ids = [azurerm_network_interface.mysql_nic.id]

  admin_ssh_key {
    username   = var.vm_admin_username
    public_key = file(var.ssh_public_key_path)
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts"
    version   = "latest"
  }

  # Provisioner para generar el inventario de Ansible
  provisioner "local-exec" {
    command = <<-EOT
      echo "[mysql]" > ../ansible/inventory
      echo "${azurerm_public_ip.mysql_public_ip.ip_address} ansible_user=${var.vm_admin_username} ansible_ssh_private_key_file=${var.ssh_private_key_path}" >> ../ansible/inventory
    EOT
  }

  # Provisioner para ejecutar Ansible
  provisioner "local-exec" {
    command = "ansible-playbook -i ../ansible/inventory ../ansible/mysql_setup.yml"
    working_dir = path.module
  }
}

# App Service Plan para la aplicación Node.js
resource "azurerm_app_service_plan" "app_plan" {
  name                = "${var.prefix}-app-plan"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  kind                = "Linux"
  reserved            = true

  sku {
    tier = "Basic"
    size = "B1"
  }
}

# App Service para la aplicación Node.js
resource "azurerm_app_service" "app" {
  name                = "${var.prefix}-app-service"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  app_service_plan_id = azurerm_app_service_plan.app_plan.id
  
  site_config {
    linux_fx_version = "NODE|14-lts"
    http2_enabled    = true
    min_tls_version  = "1.2"
  }

  # Integración con la red virtual
  app_settings = {
    "WEBSITE_NODE_DEFAULT_VERSION" = "~14"
    "DB_HOST"                      = azurerm_network_interface.mysql_nic.private_ip_address
    "DB_USER"                      = var.mysql_user
    "DB_PASSWORD"                  = var.mysql_password
    "DB_NAME"                      = var.mysql_database
  }

  # Habilitar HTTPS únicamente
  https_only = true

  # Configuración de implementación de código
  source_control {
    repo_url           = "https://github.com/bezkoder/nodejs-express-mysql"
    branch             = "master"
    manual_integration = true
    use_mercurial      = false
  }
}

# Integración de la VNET con el App Service
resource "azurerm_app_service_virtual_network_swift_connection" "vnet_integration" {
  app_service_id = azurerm_app_service.app.id
  subnet_id      = azurerm_subnet.app_subnet.id
}
