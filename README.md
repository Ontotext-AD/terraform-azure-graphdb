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

Additional steps include

- Enable [VM Encryption At Host](https://learn.microsoft.com/en-us/azure/virtual-machines/linux/disks-enable-host-based-encryption-cli)
- Register AppConfiguration with `az provider register --namespace "Microsoft.AppConfiguration"`

<!-- BEGIN_TF_DOCS -->
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
