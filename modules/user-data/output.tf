output "graphdb_vmss_user_data" {
  description = "User data script for GraphDB VM scale set."
  value       = local.user_data_script
}
