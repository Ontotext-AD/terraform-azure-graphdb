# Azure VM module

This module provisions a scaling set of GraphDB instances. It also offers basic networking.
The following variables should be set:
* graphdb_subnets
* instance_type
* lb_subnets
* network_interface_id
* resource_name_prefix
* vpc_id
* image_id
* rg_name
* node_count
* ssh_key
* source_ssh_blocks

The following external resources should be created before this module runs:
* A resource group.
* An image.
* A virtual network with two subnets:
  * A main subnet.
  * A subnet for load balancers.

TODO: At the moment, the module creates static IPs for instances in the scale set. 
This should be changed to load balancer when the `load_balancer` module is implemented.

## How to use this module

TBD

## License

This code is released under the Apache 2.0 License. See [LICENSE](LICENSE) for more details.

## Contributing

Check out the contributors guide [CONTRIBUTING.md](CONTRIBUTING.md).
