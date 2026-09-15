variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "uksouth"
}

variable "resource_group_name" {
  description = "Name of the resource group holding the whole lab."
  type        = string
  default     = "rg-lab-uksouth"
}

variable "sql_server_name" {
  description = "Globally unique name for the SQL logical server."
  type        = string
  default     = "sql-lab-hammad-01"
}

variable "sql_database_name" {
  description = "Name of the SQL database."
  type        = string
  default     = "sqldb-lab"
}

variable "key_vault_name" {
  description = "Globally unique name for the Key Vault (3-24 chars)."
  type        = string
  default     = "kv-lab-hammad-01"
}

variable "sql_admin_login" {
  description = "SQL authentication admin username."
  type        = string
  default     = "sqladmin"
}

variable "sql_admin_password" {
  description = "SQL authentication admin password. Supply via TF_VAR_sql_admin_password or a tfvars file that is never committed."
  type        = string
  sensitive   = true
}

variable "entra_admin_login" {
  description = "UPN of the Microsoft Entra administrator for the SQL server."
  type        = string
}

variable "entra_admin_object_id" {
  description = "Object ID of the Microsoft Entra administrator for the SQL server."
  type        = string
}

variable "client_ip_address" {
  description = "Public IP allowed through the SQL server firewall for local admin access. Remove once the private endpoint is in place."
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default = {
    project     = "azure-webapp-sql-lab"
    environment = "lab"
    managed_by  = "terraform"
  }
}
