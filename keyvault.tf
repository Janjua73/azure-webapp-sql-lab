resource "azurerm_key_vault" "lab" {
  name                = var.key_vault_name
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"
  tags                = var.tags

  # Azure RBAC rather than the legacy vault access policy model. With RBAC,
  # management-plane rights and data-plane rights are separate: subscription
  # Owner can delete this vault but cannot read a secret inside it without an
  # explicit data-plane role assignment.
  enable_rbac_authorization = true

  soft_delete_retention_days = 7
  purge_protection_enabled   = false # lab setting; enable in production

  public_network_access_enabled = true
}

# Data-plane access for the operator. Secrets Officer can read and write.
resource "azurerm_role_assignment" "kv_secrets_officer" {
  scope                = azurerm_key_vault.lab.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# NOTE: the SqlConnectionString secret is deliberately NOT defined here.
#
# A secret's value passed through Terraform is written in clear text into the
# state file, which is then the thing that has to be protected. Creating it
# out of band keeps the credential out of state and out of version control.
#
# Created once, manually:
#   az keyvault secret set \
#     --vault-name kv-lab-hammad-01 \
#     --name SqlConnectionString \
#     --value "<connection string>"
#
# The intended end state removes the problem entirely: with a managed identity
# as a SQL user, the connection string carries
# Authentication="Active Directory Default" and contains no credential at all.
