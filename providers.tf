terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      # 4.x is needed for the Azure SQL free-limit arguments used in sql.tf
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {
    key_vault {
      # Lab setting: let `terraform destroy` actually remove the vault rather
      # than leaving it soft-deleted and holding the name for 7 days.
      purge_soft_delete_on_destroy = true
    }
  }
}

# Used for the current tenant/object id when assigning Key Vault RBAC roles.
data "azurerm_client_config" "current" {}
