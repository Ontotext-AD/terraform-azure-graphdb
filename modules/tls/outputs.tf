output "tls_certificate_key_vault_secret_id" {
  description = "Secret identifier of the TLS certificate in the Key Vault"
  value       = azurerm_key_vault_certificate.graphdb-tls-certificate.secret_id
}

output "tls_identity_name" {
  description = "Name of the user assigned identity having permissions for reading the TLS certificate secret"
  value       = azurerm_user_assigned_identity.graphdb-tls-certificate.name
}
