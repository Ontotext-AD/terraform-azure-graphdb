module "vm" {
  source               = "./modules/vm"
  network_interface_id = var.vpc_id
  graphdb_subnets      = var.graphdb_subnets
  instance_type        = var.instance_type
  lb_subnets           = var.lb_subnets
  resource_name_prefix = var.resource_name_prefix
  image_id             = var.image_id
  rg_name              = var.rg_name
  node_count           = var.node_count
  ssh_key              = var.ssh_key
  source_ssh_blocks    = var.source_ssh_blocks
}
