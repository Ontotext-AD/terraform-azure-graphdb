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
