# Access Policy mode (no role assignments needed - works with Kodekloud restrictions)
resource "azurerm_key_vault" "kv" {
  name                        = var.key_vault_name
  location                    = var.location
  resource_group_name         = var.resource_group_name
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  sku_name                    = "standard"
  enable_rbac_authorization   = false
  soft_delete_retention_days   = 7
  purge_protection_enabled    = false
}

# Terraform identity: create and read secrets
resource "azurerm_key_vault_access_policy" "terraform" {
  key_vault_id = azurerm_key_vault.kv.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  secret_permissions = ["Get", "List", "Set", "Delete"]
}

# ESO identity: read secrets (Workload Identity)
resource "azurerm_key_vault_access_policy" "eso" {
  key_vault_id = azurerm_key_vault.kv.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_user_assigned_identity.eso.principal_id

  secret_permissions = ["Get", "List"]
}

resource "azurerm_key_vault_secret" "database_password" {
  name         = "database-password"
  value        = var.key_vault_secret_value
  key_vault_id = azurerm_key_vault.kv.id

  depends_on = [
    azurerm_key_vault_access_policy.terraform,
    azurerm_key_vault_access_policy.eso
  ]
}
