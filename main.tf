module "vm" {
  source = "./modules/vm"
  network_interface_id = var.vpc_id
  graphdb_subnets      = var.graphdb_subnets
  instance_type        = var.instance_type
  lb_subnets           = var.lb_subnets
  resource_name_prefix = var.resource_name_prefix
}