provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "nodejs_rg" {
  name     = "nodejs-mysql-rg"
  location = "East US"
}

# App Service Plan
resource "azurerm_service_plan" "nodejs_plan" {
  name                = "nodejs-appservice-plan"
  location            = azurerm_resource_group.nodejs_rg.location
  resource_group_name = azurerm_resource_group.nodejs_rg.name
  os_type             = "Linux"
  sku_name            = "B1"
}

# App Service
resource "azurerm_linux_web_app" "nodejs_app" {
  name                = "nodejs-app-${random_string.random.result}"
  location            = azurerm_resource_group.nodejs_rg.location
  resource_group_name = azurerm_resource_group.nodejs_rg.name
  service_plan_id     = azurerm_service_plan.nodejs_plan.id

  site_config {
    application_stack {
      node_version = "16-lts"
    }
    always_on = false
  }

  https_only = true
}

# MySQL VM
resource "azurerm_virtual_network" "nodejs_vnet" {
  name                = "nodejs-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.nodejs_rg.location
  resource_group_name = azurerm_resource_group.nodejs_rg.name
}

resource "azurerm_subnet" "nodejs_subnet" {
  name                 = "nodejs-subnet"
  resource_group_name  = azurerm_resource_group.nodejs_rg.name
  virtual_network_name = azurerm_virtual_network.nodejs_vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_network_interface" "mysql_nic" {
  name                = "mysql-nic"
  location            = azurerm_resource_group.nodejs_rg.location
  resource_group_name = azurerm_resource_group.nodejs_rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.nodejs_subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "mysql_vm" {
  name                = "mysql-vm"
  resource_group_name = azurerm_resource_group.nodejs_rg.name
  location            = azurerm_resource_group.nodejs_rg.location
  size                = "Standard_B1s"
  admin_username      = "adminuser"
  network_interface_ids = [
    azurerm_network_interface.mysql_nic.id,
  ]

  admin_ssh_key {
    username   = "adminuser"
    public_key = file("~/.ssh/id_rsa.pub")
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }
}

# Security rules
resource "azurerm_network_security_group" "mysql_nsg" {
  name                = "mysql-nsg"
  location            = azurerm_resource_group.nodejs_rg.location
  resource_group_name = azurerm_resource_group.nodejs_rg.name

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "186.99.122.97/32" # Tu IP
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "MySQL"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3306"
    source_address_prefix      = azurerm_linux_web_app.nodejs_app.possible_outbound_ip_addresses
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface_security_group_association" "mysql_nic_nsg" {
  network_interface_id      = azurerm_network_interface.mysql_nic.id
  network_security_group_id = azurerm_network_security_group.mysql_nsg.id
}

resource "random_string" "random" {
  length  = 8
  special = false
  upper   = false
}
