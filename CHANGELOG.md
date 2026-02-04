# GraphDB Azure Terraform Module Changelog

## 2.5.0

* Enabled Private Link for Public Application Gateways

## 2.4.1

* Update default GraphDB version to [11.2.1](https://graphdb.ontotext.com/documentation/11.2/release-notes.html#graphdb-11-2-1)

## 2.4.0

* Update default GraphDB version to [11.2.0](https://graphdb.ontotext.com/documentation/11.2/release-notes.html#graphdb-11-2-0)
* Fixed an issue where GraphDB security enabling sometimes fails due to leader election not being finished.
* Improved the reliability of the DNS assignment
* Improved the cluster rejoin logic to wait for data replication during cluster initialization
* Reduced the wait time for cluster rejoining

## 2.3.2

* Update default GraphDB version to [11.1.3](https://graphdb.ontotext.com/documentation/11.1/release-notes.html#graphdb-11-1-3)

## 2.3.1

* Upgraded hashicorp/azurerm to version 4.49.0

## 2.3.0

* `external_dns_records` module for managing Azure DNS zones (public or private) and creating DNS records (A, CNAME) with optional VNet links for private zones.
* Update default GraphDB version to [11.1.2](https://graphdb.ontotext.com/documentation/11.1/release-notes.html#graphdb-11-1-2)

## 2.2.1

* Update default GraphDB version to [11.1.1](https://graphdb.ontotext.com/documentation/11.1/release-notes.html#graphdb-11-1-1)

## 2.2.0

* Update default GraphDB version to [11.1.0](https://graphdb.ontotext.com/documentation/11.1/release-notes.html#graphdb-11-1-0)

## 2.1.0

* Added ability to provide `idle_timeout_in_minutes` for the Application Gateway Public IP
* Added ability to provide `idle_timeout_in_minutes` for the NAT Gateway Public IP
* Removed obsolete variable `gateway_backend_port` since the backend port is now automatically set based on the `node_count`

## 2.0.2

* Update default GraphDB version to [11.0.2](https://graphdb.ontotext.com/documentation/11.0/release-notes.html#graphdb-11-0-2)
* Remove sudoers.d/90-cloud-init-users
* Create gdb_backup user for backups (access to cli as well)
* Create backup user home directory

## 2.0.1

* Update default GraphDB version to [11.0.1](https://graphdb.ontotext.com/documentation/11.0/release-notes.html#graphdb-11-0-1)

## 2.0.0

* Update default GraphDB version to [11.0.0](https://graphdb.ontotext.com/documentation/11.0/release-notes.html#graphdb-11-0-0)

## 1.5.2

* Update default GraphDB version to [10.8.8](https://graphdb.ontotext.com/documentation/10.8/release-notes.html#graphdb-10-8-8)

## 1.5.1

* Update default GraphDB version to [10.8.7](https://graphdb.ontotext.com/documentation/10.8/release-notes.html#graphdb-10-8-7)

## 1.5.0

* Introduced support for deployment with an external Application Gateway.
* Added an option to configure the context path.
* Introduced changes to the Management lock policies [Resource group lock prevents node instances from being redeployed/reimaged](https://github.com/Ontotext-AD/terraform-azure-graphdb/issues/98).
* Added wait condition for DNS Records and nodes.
* Fixed handling for Monitor Reader Principal ID being `null`.
* Updated `run_backup.sh` so that the storage account name and container name are passed as script arguments.
* Fixed duplicated public IP address in `outputs.tf`.
* Added ability to provide `user_supplied_rendered_templates` and `user_supplied_templates` to the VMSS instances.
* Added check if node count is greater than 1 to use `/rest/cluster/node/status` health endpoint if not, use `/protocol`.
* Added ability to use a private IP as a FQDN if the application gateway is deployed in private mode.
* Updated AzureRM provider to version 4.17
* Changed `storage_account_name` to `storage_account_id` in `modules/backup/main.tf` since it will be removed in version 5.0 of the AzureRM provider.
* Removed `enable_https_only` in `modules/backup/main.tf` since it is not supported anymore since v4.x of the AzureRM provider.
* Updated `AzureMonitorLinuxAgent` extension for the VMSS to from 1.0 to 1.33.
* Resolved issues with new nodes joining the cluster during VMSS scale-out.
* Removed `min_tls_version` since now defaults to `1_2`.
* Updated the userdata scripts, so VMSS instance refresh is not triggered to existing instances during scale out.

## 1.4.5

* Update default GraphDB version to [10.8.5](https://graphdb.ontotext.com/documentation/10.8/release-notes.html#graphdb-10-8-5)

## 1.4.4

* Update default GraphDB version to [10.8.4](https://graphdb.ontotext.com/documentation/10.8/release-notes.html#graphdb-10-8-4)

## 1.4.3

* Update default GraphDB version to [10.8.3](https://graphdb.ontotext.com/documentation/10.8/release-notes.html#graphdb-10-8-3)

## 1.4.2

* Update default GraphDB version to [10.8.2](https://graphdb.ontotext.com/documentation/10.8/release-notes.html#graphdb-10-8-2)

## 1.4.1

* Update default GraphDB version to [10.8.1](https://graphdb.ontotext.com/documentation/10.8/release-notes.html#graphdb-10-8-1)

## 1.4.0

* Update default GraphDB version to [10.8.0](https://graphdb.ontotext.com/documentation/10.8/release-notes.html#graphdb-10-8-0)

## 1.3.4

* Update default GraphDB version to [10.7.6](https://graphdb.ontotext.com/documentation/10.7/release-notes.html#graphdb-10-7-6)

## 1.3.3

* Update default GraphDB version to [10.7.5](https://graphdb.ontotext.com/documentation/10.7/release-notes.html#graphdb-10-7-5)

## 1.3.2

* Update default GraphDB version to [10.7.4](https://graphdb.ontotext.com/documentation/10.7/release-notes.html#graphdb-10-7-4)

## 1.3.1

* Update default GraphDB version to [10.7.3](https://graphdb.ontotext.com/documentation/10.7/release-notes.html#graphdb-10-7-3)

## 1.3.0

* Improved the single node setup time by removing use and checks for Private DNS zone address.
* Update default GraphDB version to [10.7.2](https://graphdb.ontotext.com/documentation/10.7/release-notes.html#graphdb-10-7-2)

## 1.2.1

* Fixed the `graphdb.external-url` value when deploying a single node.
* Changed to create `graphdb-cluster-proxy/graphdb.properties` only when `node_count` > 1
* Update default GraphDB version to [10.7.1](https://graphdb.ontotext.com/documentation/10.7/release-notes.html#graphdb-10-7-1)

## 1.2.0

* Support for single node deployment:
  * If `node_count` is 1 and multiple availability zones are specified, only the first AZ will be used.
  * Updated Monitoring module to dynamically adjust properties based on `node_count`.
  * Updated Gateway module to dynamically adjust properties based on `node_count`.
  * For `node_count` of 1, no disk is created beforehand; the disk is created by the userdata scripts.
  * Made cluster-related userdata scripts executable only when `node_count` is greater than 1.
  * Added new userdata script `10_start_single_graphdb_services.sh.tpl` for single node setup.
* Moved some functions to `00_functions.sh` so they are reused instead of duplicated in the userdata scripts.
* Updated GraphDB version to [10.7.0](https://graphdb.ontotext.com/documentation/10.7/release-notes.html)

## 1.1.1

* Updated GraphDB version to [10.6.4](https://graphdb.ontotext.com/documentation/10.6/release-notes.html#graphdb-10-6-4)

## 1.1.0

### New Features & Enhancements
* Support for 3+ nodes Clusters:
  * Enabled automatic creation of clusters with more than 3 nodes.
  * Removed the upper limit on the number of nodes in a cluster.
  * Introduced a check for total quorum availability before a node joins the cluster.
  * Added a retry mechanism for cluster join operations in case of initial failure.
* GraphDB License Check:
  * Added a check for GraphDB license being applied before creating the cluster.
* Time Stamps:
  * Added time stamps to templated user data scripts.
* Shell Options:
  * Updated shell options for better descriptiveness.
* Helper Functions:
  * Introduced 00_functions.sh for common helper functions.
* User Data Scripts:
  * Added a mechanism to include additional user data scripts via the `user_supplied_scripts` variable.
  * Enhanced readability.
  * Improved handling of corner cases during cluster scaling.
  * Added protections against race conditions when attaching volumes.
  * Changed cluster creation to be based on available DNS records in the Private DNS zone.
* DNS Resolution:
  * Added `dns_servers = ["168.63.129.16"]` to VMSS for resolving Private DNS zone records even with custom DNS servers set for the Virtual Network.
* Deployment Flexibility:
  * Added support for deploying the Terraform module in existing Resource Groups and Virtual Networks.

### Fixes
* Monitoring Deployment:
  * Fixed the deployment of `azurerm_monitor_diagnostic_setting` for key vaults when monitoring is enabled.
  * Fixed an issue where wrong DNS address is set after scale in/out of nodes.

## 1.0.1

Updated GraphDB version to [10.6.3](https://graphdb.ontotext.com/documentation/10.6/release-notes.html#graphdb-10-6-3)

## 1.0.0

First release of the official Terraform module for deploying GraphDB on Microsoft Azure.
