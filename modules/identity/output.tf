output "identity_name" {
  description = "Name of the user assigned identity"
  value       = azurerm_user_assigned_identity.graphdb-instances.name
}
