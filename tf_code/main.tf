# Azure provider - features block is required
# skip_provider_registration: use when identity lacks permission to register Resource Providers (e.g. limited Kodekloud account)
provider "azurerm" {
  features {}
  skip_provider_registration = true
}

# Data sources
data "azurerm_client_config" "current" {}

# Note: Using variables instead of data source to avoid resource group read permission requirement
# (Kodekloud/limited accounts may lack Microsoft.Resources/subscriptions/resourcegroups/read)

# Outputs
output "aks_name" {
  value       = azurerm_kubernetes_cluster.aks.name
  description = "Name of the AKS cluster"
}

output "resource_group_name" {
  value       = var.resource_group_name
  description = "Resource group name"
}

output "key_vault_uri" {
  value       = azurerm_key_vault.kv.vault_uri
  description = "Azure Key Vault URI"
}

output "kube_config_command" {
  value       = "az aks get-credentials --resource-group ${var.resource_group_name} --name ${azurerm_kubernetes_cluster.aks.name}"
  description = "Command to configure kubectl"
}

output "tenant_id" {
  value       = data.azurerm_client_config.current.tenant_id
  description = "Azure tenant ID (for ClusterSecretStore)"
}

output "vault_uri" {
  value       = azurerm_key_vault.kv.vault_uri
  description = "Key Vault URI (for ClusterSecretStore)"
}

output "eso_client_id" {
  value       = azurerm_user_assigned_identity.eso.client_id
  description = "ESO Workload Identity Client ID (for Service Account annotations)"
}

output "oidc_issuer_url" {
  value       = azurerm_kubernetes_cluster.aks.oidc_issuer_url
  description = "AKS OIDC issuer URL (for federated identity)"
}
