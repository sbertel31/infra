# outputs.tf - Salidas de la infraestructura

output "resource_group_name" {
  value = azurerm_resource_group.rg.name
}

output "mysql_vm_public_ip" {
  value = azurerm_public_ip.mysql_public_ip.ip_address
}

output "mysql_vm_private_ip" {
  value = azurerm_network_interface.mysql_nic.private_ip_address
}

output "app_service_url" {
  value = "https://${azurerm_app_service.app.default_site_hostname}"
}
