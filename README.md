# GraphDB Azure Terraform Module

[![CI](https://github.com/Ontotext-AD/terraform-azure-graphdb/actions/workflows/ci.yml/badge.svg)](https://github.com/Ontotext-AD/terraform-azure-graphdb/actions/workflows/ci.yml)

This repository contains a set of [Terraform](https://www.terraform.io/) modules for
deploying [Ontotext GraphDB](https://www.ontotext.com/products/graphdb/)
HA cluster on [Microsoft Azure](https://azure.microsoft.com/).

## Table of Contents

- [About GraphDB](#about-graphdb)
- [Features](#features)
- [Prerequisites](#prerequisites)
- [Configurations](#configurations)
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

<!---
TODO link to azure marketplace?
-->

## Features

The module provides the building blocks of configuring, deploying and provisioning a highly available cluster of GraphDB across multiple availability
zones using a VM scale set. Key features of the module include:

- Azure VM scale set across multiple Availability Zones
- Azure Application Gateway for load balancing and TLS termination
- Azure NAT gateway for outbound connections
- Automated backups in Azure Blob Storage
- Azure Private DNS for internal GraphDB cluster communication
- Azure Key Vault for storing sensitive configurations
- Optional Azure Bastion deployment
- User assigned identities for RBAC authorization with the least privilege principle
- and more

<!---
TODO list the key features of the module as well as the purpose of the modules + maybe some diagram?
See https://github.com/hashicorp/terraform-aws-consul
-->

## Prerequisites

- Subscription in Microsoft Azure
- Azure CLI https://learn.microsoft.com/en-us/cli/azure/install-azure-cli
- Terraform CLI v1.5+ https://developer.hashicorp.com/terraform/install?product_intent=terraform
- License for GraphDB Enterprise Edition

You then need to authenticate in your subscription with Azure CLI,
see [Authenticating using the Azure CLI](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/guides/azure_cli) for more details.

## Configurations

The module support different variables that customize the deployment. Inside [variables.tf](variables.tf) you can see all the supported
options.

<!-- BEGIN_TF_DOCS -->

| Name                                  | Description                                                                                                                          | Type           | Default                 | Required |
|---------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------|----------------|-------------------------|:--------:|
| resource\_name\_prefix                | Resource name prefix used for tagging and naming Azure resources                                                                     | `string`       | n/a                     |   yes    |
| location                              | Azure geographical location where resources will be deployed                                                                         | `string`       | n/a                     |   yes    |
| zones                                 | Availability zones to use for resource deployment and HA                                                                             | `list(number)` | ```[ 1, 2, 3 ]```       |    no    |
| tags                                  | Common resource tags.                                                                                                                | `map(string)`  | `{}`                    |    no    |
| lock\_resources                       | Enables a delete lock on the resource group to prevent accidental deletions.                                                         | `bool`         | `true`                  |    no    |
| virtual\_network\_address\_space      | Virtual network address space CIDRs.                                                                                                 | `list(string)` | ```[ "10.0.0.0/16" ]``` |    no    |
| app\_gateway\_subnet\_address\_prefix | Subnet address prefix CIDRs where the application gateway will reside.                                                               | `list(string)` | ```[ "10.0.1.0/24" ]``` |    no    |
| graphdb\_subnet\_address\_prefix      | Subnet address prefix CIDRs where GraphDB VMs will reside.                                                                           | `list(string)` | ```[ "10.0.2.0/24" ]``` |    no    |
| management\_cidr\_blocks              | CIDR blocks allowed to perform management operations such as connecting to Bastion or Key Vault.                                     | `list(string)` | n/a                     |   yes    |
| tls\_certificate\_path                | Path to a TLS certificate that will be imported in Azure Key Vault and used in the Application Gateway TLS listener for GraphDB.     | `string`       | n/a                     |   yes    |
| tls\_certificate\_password            | TLS certificate password for password protected certificates.                                                                        | `string`       | `null`                  |    no    |
| key\_vault\_enable\_purge\_protection | Prevents purging the key vault and its contents by soft deleting it. It will be deleted once the soft delete retention has passed.   | `bool`         | `false`                 |    no    |
| key\_vault\_retention\_days           | Retention period in days during which soft deleted secrets are kept                                                                  | `number`       | `30`                    |    no    |
| graphdb\_version                      | GraphDB version to deploy                                                                                                            | `string`       | `"10.4.1"`              |    no    |
| graphdb\_image\_id                    | Image ID to use for running GraphDB VM instances. If left unspecified, Terraform will use the image from our public Compute Gallery. | `string`       | `null`                  |    no    |
| graphdb\_license\_path                | Local path to a file, containing a GraphDB Enterprise license.                                                                       | `string`       | n/a                     |   yes    |
| graphdb\_cluster\_token               | Secret token used to secure the internal GraphDB cluster communication. Will generate one if left undeclared.                        | `string`       | `null`                  |    no    |
| graphdb\_password                     | Secret token used to access GraphDB cluster.                                                                                         | `string`       | `null`                  |    no    |
| graphdb\_properties\_path             | Path to a local file containing GraphDB properties (graphdb.properties) that would be appended to the default in the VM.             | `string`       | `null`                  |    no    |
| graphdb\_java\_options                | GraphDB options to pass to GraphDB with GRAPHDB\_JAVA\_OPTS environment variable.                                                    | `string`       | `null`                  |    no    |
| node\_count                           | Number of GraphDB nodes to deploy in ASG                                                                                             | `number`       | `3`                     |    no    |
| instance\_type                        | Azure instance type                                                                                                                  | `string`       | n/a                     |   yes    |
| ssh\_key                              | Public key for accessing the GraphDB instances                                                                                       | `string`       | `null`                  |    no    |
| custom\_graphdb\_vm\_user\_data       | Custom user data script used during the cloud init phase in the GraphDB VMs. Should be in base64 encoding.                           | `string`       | `null`                  |    no    |
| storage\_account\_tier                | Specify the performance and redundancy characteristics of the Azure Storage Account that you are creating                            | `string`       | `"Standard"`            |    no    |
| storage\_account\_replication\_type   | Specify the data redundancy strategy for your Azure Storage Account                                                                  | `string`       | `"ZRS"`                 |    no    |
| backup\_schedule                      | Cron expression for the backup job.                                                                                                  | `string`       | `"0 0 * * *"`           |    no    |
| disk\_size\_gb                        | Size of the managed data disk which will be created                                                                                  | `number`       | `500`                   |    no    |
| disk\_iops\_read\_write               | Data disk IOPS                                                                                                                       | `number`       | `7500`                  |    no    |
| disk\_mbps\_read\_write               | Data disk throughput                                                                                                                 | `number`       | `250`                   |    no    |
| deploy\_bastion                       | Deploy bastion module                                                                                                                | `bool`         | `false`                 |    no    |
| bastion\_subnet\_address\_prefix      | Bastion subnet address prefix                                                                                                        | `list(string)` | ```[ "10.0.3.0/27" ]``` |    no    |

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

**Bastion**

To enable the deployment of Azure Bastion, you simply need to enable the following flag:

```hcl
deploy_bastion = true
```

**GraphDB admin password**

Instead of generating a random administrator password, you can provide one with:

```hcl
graphdb_password = "s3cr37P@$w0rD"
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
