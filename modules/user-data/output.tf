output "graphdb_vmss_user_data" {
  description = "User data script for GraphDB VM scale set."
  value       = data.cloudinit_config.entrypoint.rendered
}
