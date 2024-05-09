# GraphDB Azure Terraform Module

[![CI](https://github.com/Ontotext-AD/terraform-azure-graphdb/actions/workflows/ci.yml/badge.svg)](https://github.com/Ontotext-AD/terraform-azure-graphdb/actions/workflows/ci.yml)
![GitHub Release](https://img.shields.io/github/v/release/Ontotext-AD/terraform-azure-graphdb?display_name=tag)

This repository contains a set of [Terraform](https://www.terraform.io/) modules for
deploying [Ontotext GraphDB](https://www.ontotext.com/products/graphdb/)
HA cluster on [Microsoft Azure](https://azure.microsoft.com/).

## Table of Contents

- [About GraphDB](#about-graphdb)
- [Features](#features)
- [Versioning](#versioning)
- [Prerequisites](#prerequisites)
- [Inputs](#inputs)
- [Usage](#usage)
- [Examples](#examples)
- [Local Development](#local-development)
- [Release History](#release-history)
- [Contributing](#contributing)
- [License](#license)

## About GraphDB

<p align="center">
  <a href="https://www.ontotext.com/products/graphdb/">
    <picture>
      <img src="https://www.ontotext.com/wp-content/uploads/2022/09/Logo-GraphDB.svg" alt="GraphDB logo" title="GraphDB" height="75">
    </picture>
  </a>
</p>

Ontotext GraphDB is a highly efficient, scalable and robust graph database with RDF and SPARQL support. With excellent enterprise features,
integration with external search applications, compatibility with industry standards, and both community and commercial support, GraphDB is the
preferred database choice of both small independent developers and big enterprises.

GraphDB is available on the [Azure Marketplace](https://azuremarketplace.microsoft.com/en-us/marketplace/apps?search=Ontotext%20AD)
in several listings depending on your needs.

## Features

The module provides the building blocks of configuring, deploying and provisioning a highly available cluster of GraphDB across multiple availability
zones using a VM scale set. Key features of the module include:

- Azure VM scale set across multiple Availability Zones
- Azure Application Gateway for load balancing and TLS termination
- Azure Private Link with private Application Gateway
- Azure NAT gateway for outbound connections
- Automated backups in Azure Blob Storage
- Azure Private DNS for internal GraphDB cluster communication
- Azure Key Vault for storing sensitive configurations
- Optional Azure Bastion deployment
- User assigned identities for RBAC authorization with the least privilege principle
- and more

## Modules Overview

| Modules                    | Purpose                                                                                                           | Features                                                                                                                                                          |
|----------------------------|-------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Vault Module               | Creates a Key Vault for storing TLS certificates and secrets                                                      | - Enables purge protection for Key Vault.<br/> - Sets soft delete retention days for Key Vault.                                                                   |
| Backup Module              | Sets up a Storage Account for storing GraphDB backups.                                                            | - Configures storage account tier and replication type.<br/> - Defines retention policies for storage blobs and containers.                                       |
| AppConfig Module           | Establishes an App Configuration store for managing GraphDB configurations.                                       | - Enables purge protection for App Configuration. <br/> - Sets soft delete retention days for App Configuration.                                                  |
| TLS Module                 | Manages TLS certificate secrets in Key Vault and their related identities.                                        | - Creates TLS certificate secrets in Key Vault.<br/> - Configures identity related to the TLS certificate.                                                        |
| Application Gateway Module | Sets up a public IP address and Application Gateway for forwarding internet traffic to GraphDB proxies/instances. | - Configures TLS certificate for the gateway.<br/> - Enables private access and private link service.<br/> - Defines global buffer settings.                      |
| Bastion Module             | Deploys an Azure Bastion host for secure remote connections.                                                      | - Configures the bastion host within the specified virtual network.                                                                                               |
| Monitoring Module          | Configures Azure monitoring for the deployed resources.                                                           | - Sets up Application Insights for the GraphDB scale set.<br/> - Sets up web test availability monitoring.<br/> - Defines retention policies for monitoring data. |
| GraphDB Module             | Deploys a VM scale set for GraphDB and its cluster proxies.                                                       | - Configures networking settings.<br/> - Sets up GraphDB configurations and licenses.<br/> - Defines backup storage, VM image, and managed disk settings.         |

<!---
TODO list the key features of the module as well as the purpose of the modules + maybe some diagram?
See https://github.com/hashicorp/terraform-aws-consul
-->

## Versioning

The Terraform module follows the [Semantic Versioning 2.0.0](https://semver.org/) rules and has a release lifecycle separate from the GraphDB
versions. The next table shows the version compatability between GraphDB and the Terraform module.

| GraphDB Terraform | GraphDB        |
|-------------------|----------------|
| Version 1.x.x     | Version 10.6.x |

You can track the particular version updates of GraphDB in the [changelog](CHANGELOG.md) or
the [release notes](https://github.com/Ontotext-AD/terraform-azure-graphdb/releases).

## Prerequisites

- Subscription in Microsoft Azure
- Azure CLI https://learn.microsoft.com/en-us/cli/azure/install-azure-cli
- Terraform CLI v1.5+ https://developer.hashicorp.com/terraform/install?product_intent=terraform
- License for GraphDB Enterprise Edition

You then need to authenticate in your subscription with Azure CLI,
see [Authenticating using the Azure CLI](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/guides/azure_cli) for more details.

Additional steps include:

- Enable [VM Encryption At Host](https://learn.microsoft.com/en-us/azure/virtual-machines/linux/disks-enable-host-based-encryption-cli)
- Register AppConfiguration with `az provider register --namespace "Microsoft.AppConfiguration"`
- Register AllowApplicationGatewayPrivateLink with `az feature register --name AllowApplicationGatewayPrivateLink --namespace Microsoft.Network` if
  you are planning on using Private Link

The Terraform module deploys a VM scale set based on a VM image published in the Azure Marketplace.
This requires you to accept the terms which can be accomplished with Azure CLI:

```bash
az vm image accept-terms --offer graphdb-ee --plan graphdb-byol --publisher ontotextad1692361256062
```

<!-- BEGIN_TF_DOCS -->
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| resource\_name\_prefix | Resource name prefix used for tagging and naming Azure resources | `string` | n/a | yes |
| location | Azure geographical location where resources will be deployed | `string` | n/a | yes |
| zones | Availability zones to use for resource deployment and HA | `list(number)` | ```[ 1, 2, 3 ]``` | no |
| tags | Common resource tags. | `map(string)` | `{}` | no |
| lock\_resources | Enables a delete lock on the resource group to prevent accidental deletions. | `bool` | `true` | no |
| graphdb\_external\_address\_fqdn | External FQDN address for the deployment | `string` | `null` | no |
| virtual\_network\_address\_space | Virtual network address space CIDRs. | `list(string)` | ```[ "10.0.0.0/16" ]``` | no |
| gateway\_subnet\_address\_prefixes | Subnet address prefixes CIDRs where the application gateway will reside. | `list(string)` | ```[ "10.0.1.0/24" ]``` | no |
| graphdb\_subnet\_address\_prefixes | Subnet address prefixes CIDRs where GraphDB VMs will reside. | `list(string)` | ```[ "10.0.2.0/24" ]``` | no |
| gateway\_private\_link\_subnet\_address\_prefixes | Subnet address prefixes where the Application Gateway Private Link will reside, if enabled | `list(string)` | ```[ "10.0.5.0/24" ]``` | no |
| management\_cidr\_blocks | CIDR blocks allowed to perform management operations such as connecting to Bastion or Key Vault. | `list(string)` | n/a | yes |
| inbound\_allowed\_address\_prefix | Source address prefix allowed for connecting to the application gateway | `string` | `"Internet"` | no |
| inbound\_allowed\_address\_prefixes | Source address prefixes allowed for connecting to the application gateway. Overrides inbound\_allowed\_address\_prefix | `list(string)` | `[]` | no |
| outbound\_allowed\_address\_prefix | Destination address prefix allowed for outbound traffic from GraphDB | `string` | `"Internet"` | no |
| outbound\_allowed\_address\_prefixes | Destination address prefixes allowed for outbound traffic from GraphDB. Overrides outbound\_allowed\_address\_prefix | `list(string)` | `[]` | no |
| gateway\_global\_request\_buffering\_enabled | Whether Application Gateway's Request buffer is enabled. | `bool` | `true` | no |
| gateway\_global\_response\_buffering\_enabled | Whether Application Gateway's Response buffer is enabled. | `bool` | `true` | no |
| gateway\_enable\_private\_access | Enable or disable private access to the application gateway | `bool` | `false` | no |
| gateway\_enable\_private\_link\_service | Set to true to enable Private Link service, false to disable it. | `bool` | `false` | no |
| gateway\_private\_link\_service\_network\_policies\_enabled | Enable or disable private link service network policies | `string` | `false` | no |
| tls\_certificate\_path | Path to a TLS certificate that will be imported in Azure Key Vault and used in the Application Gateway TLS listener for GraphDB. | `string` | `null` | no |
| tls\_certificate\_password | TLS certificate password for password protected certificates. | `string` | `null` | no |
| tls\_certificate\_id | Resource identifier for a TLS certificate secret from a Key Vault. Overrides tls\_certificate\_path | `string` | `null` | no |
| tls\_certificate\_identity\_id | Identifier of a managed identity giving access to the TLS certificate specified with tls\_certificate\_id | `string` | `null` | no |
| key\_vault\_enable\_purge\_protection | Prevents purging the key vault and its contents by soft deleting it. It will be deleted once the soft delete retention has passed. | `bool` | `true` | no |
| key\_vault\_soft\_delete\_retention\_days | Retention period in days during which soft deleted secrets are kept | `number` | `30` | no |
| app\_config\_enable\_purge\_protection | Prevents purging the App Configuration and its keys by soft deleting it. It will be deleted once the soft delete retention has passed. | `bool` | `true` | no |
| app\_config\_soft\_delete\_retention\_days | Retention period in days during which soft deleted keys are kept | `number` | `7` | no |
| admin\_security\_principle\_id | UUID of a user or service principle that will become data owner or administrator for specific resources that need permissions to insert data during Terraform apply, i.e. KeyVault and AppConfig. If left unspecified, the current user will be used. | `string` | `null` | no |
| graphdb\_version | GraphDB version from the marketplace offer | `string` | `"10.6.3"` | no |
| graphdb\_sku | GraphDB SKU from the marketplace offer | `string` | `"graphdb-byol"` | no |
| graphdb\_image\_id | GraphDB image ID to use for the scale set VM instances in place of the default marketplace offer | `string` | `null` | no |
| graphdb\_license\_path | Local path to a file, containing a GraphDB Enterprise license. | `string` | n/a | yes |
| graphdb\_cluster\_token | Secret token used to secure the internal GraphDB cluster communication. Will generate one if left undeclared. | `string` | `null` | no |
| graphdb\_password | Secret token used to access GraphDB cluster. | `string` | `null` | no |
| graphdb\_properties\_path | Path to a local file containing GraphDB properties (graphdb.properties) that would be appended to the default in the VM. | `string` | `null` | no |
| graphdb\_java\_options | GraphDB options to pass to GraphDB with GRAPHDB\_JAVA\_OPTS environment variable. | `string` | `null` | no |
| node\_count | Number of GraphDB nodes to deploy in ASG | `number` | `3` | no |
| instance\_type | Azure instance type | `string` | n/a | yes |
| ssh\_key | Public key for accessing the GraphDB instances | `string` | `null` | no |
| storage\_account\_tier | Specify the performance and redundancy characteristics of the Azure Storage Account that you are creating | `string` | `"Standard"` | no |
| storage\_account\_replication\_type | Specify the data redundancy strategy for your Azure Storage Account | `string` | `"ZRS"` | no |
| storage\_blobs\_max\_days\_since\_creation | Specifies the retention period in days since creation before deleting storage blobs | `number` | `31` | no |
| storage\_account\_retention\_hot\_to\_cool | Specifies the retention period in days between moving data from hot to cool tier storage | `number` | `3` | no |
| storage\_container\_soft\_delete\_retention\_policy | Number of days for retaining the storage container from actual deletion | `number` | `31` | no |
| storage\_blob\_soft\_delete\_retention\_policy | Number of days for retaining storage blobs from actual deletion | `number` | `31` | no |
| backup\_schedule | Cron expression for the backup job. | `string` | `"0 0 * * *"` | no |
| deploy\_bastion | Deploy bastion module | `bool` | `false` | no |
| bastion\_subnet\_address\_prefixes | Bastion subnet address prefixes | `list(string)` | ```[ "10.0.3.0/26" ]``` | no |
| deploy\_monitoring | Deploy monitoring module | `bool` | `true` | no |
| disk\_size\_gb | Size of the managed data disk which will be created | `number` | `500` | no |
| disk\_iops\_read\_write | Data disk IOPS | `number` | `7500` | no |
| disk\_mbps\_read\_write | Data disk throughput | `number` | `250` | no |
| disk\_storage\_account\_type | Storage account type for the data disks | `string` | `"PremiumV2_LRS"` | no |
| disk\_network\_access\_policy | Network accesss policy for the managed disks | `string` | `"DenyAll"` | no |
| disk\_public\_network\_access | Public network access enabled for the managed disks | `bool` | `false` | no |
| la\_workspace\_retention\_in\_days | The workspace data retention in days. Possible values are either 7 (Free Tier only) or range between 30 and 730. | `number` | `30` | no |
| la\_workspace\_sku | Specifies the SKU of the Log Analytics Workspace. Possible values are Free, PerNode, Premium, Standard, Standalone, Unlimited, CapacityReservation, and PerGB2018 (new SKU as of 2018-04-03). Defaults to PerGB2018. | `string` | `"PerGB2018"` | no |
| appi\_retention\_in\_days | Specifies the retention period in days. | `number` | `30` | no |
| appi\_daily\_data\_cap\_in\_gb | Specifies the Application Insights component daily data volume cap in GB. | `number` | `1` | no |
| appi\_daily\_data\_cap\_notifications\_disabled | Specifies if a notification email will be send when the daily data volume cap is met. | `bool` | `false` | no |
| appi\_disable\_ip\_masking | By default the real client IP is masked as 0.0.0.0 in the logs. Use this argument to disable masking and log the real client IP | `bool` | `true` | no |
| appi\_web\_test\_availability\_enabled | Should the availability web test be enabled | `bool` | `true` | no |
| web\_test\_ssl\_check\_enabled | Should the SSL check be enabled? | `bool` | `false` | no |
| web\_test\_geo\_locations | A list of geo locations the test will be executed from | `list(string)` | ```[ "us-va-ash-azr", "us-il-ch1-azr", "emea-gb-db3-azr", "emea-nl-ams-azr", "apac-hk-hkn-azr" ]``` | no |
| monitor\_reader\_principal\_id | Principal(Object) ID of a user/group which would receive notifications from alerts. | `string` | `null` | no |
| notification\_recipients\_email\_list | List of emails which will be notified via e-mail and/or push notifications | `list(string)` | `[]` | no |
<!-- END_TF_DOCS -->

## Usage

To use the GraphDB module, create a new Terraform project or add to an existing one the following module block:

```hcl
module "graphdb" {
  source  = "Ontotext-AD/graphdb/azure"
  version = "1.0.0"

  resource_name_prefix = "graphdb"
  location             = "East US"
  zones                = [1, 2, 3]
  tags                 = {
    Environment : "dev"
  }

  instance_type          = "Standard_E8as_v5"
  graphdb_license_path   = "path-to-graphdb-license"
  ssh_key                = "your-public-key"
  management_cidr_blocks = ["your-ip-address"]
  tls_certificate_path   = "path-to-your-tls-certificate"
}
```

Initialize the module and its required providers with:

```bash
terraform init
```

Before deploying, make sure to inspect the plan output with:

```bash
terraform plan
```

After a careful review of the output plan, deploy with:

```bash
terraform apply
```

Once deployed, you should be able to access the environment at the generated FQDN that has been outputted at the end.

## Examples

**GraphDB Secrets**

Instead of generating a random administrator password, you can provide one with:

```hcl
graphdb_password = "s3cr37P@$w0rD"
```

It's the same with the shared GraphDB cluster secret, to override the randomly generated password, use:

```hcl
graphdb_cluster_secret = "V6'vj|G]fpQ1_^9_,AE(r}Ct9yKuF&"
```

**GraphDB Configurations**

The GraphDB instances can be customized either by providing a custom `graphdb.properties` file that could contain any of the
supported [GraphDB configurations properties](https://graphdb.ontotext.com/documentation/10.6/directories-and-config-properties.html#configuration):

```hcl
graphdb_properties_path = "<path_to_custom_graphdb_properties_file>"
```

Or by setting the `GDB_JAVA_OPTS` environment variable with `graphdb_java_options`. For example, if you want to print the command line flags, use:

```hcl
graphdb_java_options = "-XX:+PrintCommandLineFlags"
```

**Bastion**

To enable the deployment of Azure Bastion, you simply need to enable the following flag:

```hcl
deploy_bastion = true
```

**Private Gateway with Private Link**

To enable the Private Link service on a private Application Gateway, you need to enable the following flags:

```hcl
gateway_enable_private_access       = true
gateway_enable_private_link_service = true
```

See [Configure Azure Application Gateway Private Link](https://learn.microsoft.com/en-us/azure/application-gateway/private-link-configure?tabs=portal)
for further information on configuring and using Application Gateway Private Link.

**Providing a TLS certificate**

There are two options for setting up the Application Gateway with a TLS certificate.

1. Provide local certificate file in PFX format with:
    ```hcl
    tls_certificate_path     = "path-to-your-tls-certificate"
    tls_certificate_password = "tls-certificate-password"     # Optional
    ```
   Note: This will create a dedicated Key Vault for storing the certificate.
2. Or provide a reference to an existing TLS certificate with:
    ```hcl
    tls_certificate_id          = "key-vault-certificate-secret-id"
    tls_certificate_identity_id = "managed-identity-id"
    ```

**Purge Protection**

Resources that support purge protection and soft delete have them enabled by default.
You can override the default configurations with the following variables:

```hcl
# Make sure the resource group delete lock is enabled for production
lock_resources = true

# Configure Key Vault purge protection in case of local TLS certificate usage
key_vault_enable_purge_protection    = true
key_vault_soft_delete_retention_days = 7 # From 7 to 90 days

app_config_enable_purge_protection    = true
app_config_soft_delete_retention_days = 7 # From 1 to 7 days

storage_container_soft_delete_retention_policy = 7 # From 1 to 365 days
storage_blob_soft_delete_retention_policy      = 7 # From 1 to 365 days
```

**Managed Disks**

Depending on the amount of data, expected statements or other factors, you might want to reconfigure the default options used for provisioning managed
disks for persistent storage.

```hcl
disk_size_gb         = 1250
disk_iops_read_write = 16000
disk_mbps_read_write = 1000
```

**Monitoring**

Resources related to the monitoring (Application Insights) are deployed by default, you can change this with

```hcl
deploy_monitoring = false
```

**Custom GraphDB VM Image**

You can provide the VMSS with a custom VM image by specifying `graphdb_image_id`, for example:

```hcl
graphdb_image_id = "/subscriptions/<subscription_id>/resourceGroups/<resource_group_name>/providers/Microsoft.Compute/galleries/<gallery_name>/images/<image_definition_name>/versions/<image_version>"
```

<!---
TODO Add more examples
-->

<!---
## Next Steps

TODO Configure security, provisioning etc. links for loading data? backend for state
-->

## Local Development

Instead of using the module as dependency, you can create a local variables file named `terraform.tfvars` and provide configuration overrides there.
Then simply follow the same steps as in the [Usage](#usage) section.

## Release History

All notable changes between version are tracked and documented at [CHANGELOG.md](CHANGELOG.md).

## Contributing

Check out the contributors guide [CONTRIBUTING.md](CONTRIBUTING.md).

## License

This code is released under the Apache 2.0 License. See [LICENSE](LICENSE) for more details.

<!---
TODO Do we need a copyright statement? Even if the code is released under Apache?
-->
