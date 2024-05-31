# NAT gateway

output "nat_public_ip_address" {
  description = "The public IPv4 address for the NAT gateway"
  value       = azurerm_public_ip.graphdb_nat_gateway.ip_address
}

output "nat_public_ip_address_id" {
  description = "Identifier of the public IP address for the NAT gateway"
  value       = azurerm_public_ip.graphdb_nat_gateway.id
}

# Private DNS

output "graphdb_private_dns_zone_id" {
  description = "Identifier of the private DNS zone for GraphDB"
  value       = azurerm_private_dns_zone.graphdb.id
}

# Identity

output "graphdb_vmss_identity_id" {
  description = "Identifier of the user assigned identity for GraphDB VMSS"
  value       = azurerm_user_assigned_identity.graphdb_vmss.id
}

output "graphdb_vmss_identity_name" {
  description = "Name of the user assigned identity for GraphDB VMSS"
  value       = azurerm_user_assigned_identity.graphdb_vmss.name
}

output "graphdb_vmss_identity_principal_id" {
  description = "Principal identifier of the user assigned identity for GraphDB VMSS"
  value       = azurerm_user_assigned_identity.graphdb_vmss.principal_id
}

# User data

output "graphdb_vmss_user_data" {
  description = "User data script for GraphDB VM scale set."
  value       = data.cloudinit_config.entrypoint.rendered
}

# VMSS

output "vmss_resource_id" {
  description = "Identifier of the created VMSS resource"
  value       = azurerm_orchestrated_virtual_machine_scale_set.graphdb.id
}

# NSGs

output "application_security_group_id" {
  description = "Identifier of the application security group assigned to GraphDB VMSS"
  value       = azurerm_application_security_group.graphdb_vmss.id
}

output "network_security_group_id" {
  description = "Identifier of the network security group assigned to GraphDB VMSS subnet"
  value       = azurerm_network_security_group.graphdb_vmss.id
}
