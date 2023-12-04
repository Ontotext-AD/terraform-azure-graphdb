output "identity_name" {
  description = "Name of the user assigned identity"
  value       = azurerm_user_assigned_identity.graphdb_instances.name
}

output "identity_id" {
  description = "Identifier of the user assigned identity"
  value       = azurerm_user_assigned_identity.graphdb_instances.id
}

output "identity_principal_id" {
  description = "Principal identifier of the user assigned identity"
  value       = azurerm_user_assigned_identity.graphdb_instances.principal_id
}
