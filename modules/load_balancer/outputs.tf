output "load_balancer_id" {
  description = "Identifier of the load balancer for GraphDB"
  value       = azurerm_lb.graphdb.id
}

output "load_balancer_backend_address_pool_id" {
  description = "Identifier of the load balancer backend pool for GraphDB nodes"
  value       = azurerm_lb_backend_address_pool.graphdb.id
}

# TODO: or output provided one (if any)
output "load_balancer_fqdn" {
  description = "FQDN of the load balancer for GraphDB"
  value       = azurerm_public_ip.graphdb-load-balancer.fqdn
}
