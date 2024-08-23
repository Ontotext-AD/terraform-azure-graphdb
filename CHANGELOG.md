# GraphDB Azure Terraform Module Changelog

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
