terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.91.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~>3.6.0"
    }
    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "~>2.3.3"
    }
  }
}
