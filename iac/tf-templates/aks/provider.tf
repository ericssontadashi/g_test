terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "3.117.1"
    }
  }
}

provider "azurerm" {
  tenant_id       = var.tenant_id
  subscription_id = var.provider_config["subscription_id"]
  features {}
}

provider "azurerm" {
  alias = "network"
  tenant_id       = var.tenant_id
  subscription_id = var.provider_dns["subscription_id"]
  features {}
}

