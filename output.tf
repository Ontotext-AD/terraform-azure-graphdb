output "load_balancer_fqdn" {
  description = "FQDN of the load balancer for GraphDB"
  value       = module.load_balancer.load_balancer_fqdn
}
