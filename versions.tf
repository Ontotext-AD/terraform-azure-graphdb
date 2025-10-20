terraform {
  required_version = "~>1.9"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>4.49.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~>3.6.0"
    }
    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "~>2.3.3"
    }
    time = {
      source  = "hashicorp/time"
      version = "~>0.10.0"
    }
  }
}
