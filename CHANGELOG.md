# GraphDB Azure Terraform Module Changelog

## 1.1.0

* Introduced support for automatically creating more than a 3 node cluster.
  * Refactored 02_disk_management.sh.tpl to be more readable and handle corner cases when scaling up the cluster.
  * Added protections for raise conditions when attaching volumes.
  * Refactored 03_dns_provisioning.sh.tpl to create more than 3 DNS records. Currently there is no upper limit for nodes when creating the cluster.
  * Refactored 08_cluster_setup.sh.tpl, made the cluster creation to be based on the available DNS records in the Private DNS zone.
  * Added check for the GraphDB license, the script will exit if the license is not properly applied to GraphDB.
  * Renamed 09_cluster_rejoin.sh.tpl to 09_cluster_join.sh.tpl, refactored the script to work with the records in the Private DNS zone, instead of being hardcoded.
  * Added check for total quorum availability before node joining the cluster.
  * Removed useless if check before waiting for the raft folder existence.
  * Added retry mechanism for cluster join if the operation initially fails.

* Added time stamps to the templated user data scripts.
  * Added 00_functions.sh for helper functions
* Updated the shell options to be more descriptive.
* Fixed the deployment of `azurerm_monitor_diagnostic_setting` for the key vault when monitoring is enabled
* Introduced a mechanism to provide additional user data scripts via the `user_supplied_scripts` variable.
* Added `dns_servers = ["168.63.129.16"]` to the VMSS. This allows the Private DNS zone records to be resolved
even if a custom DNS server is set for the Virtual Network.


## 1.0.1

Updated GraphDB version to [10.6.3](https://graphdb.ontotext.com/documentation/10.6/release-notes.html#graphdb-10-6-3)

## 1.0.0

First release of the official Terraform module for deploying GraphDB on Microsoft Azure.
