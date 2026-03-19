# User-assigned Managed Identity for ESO (Workload Identity - no ClientSecret)
resource "azurerm_user_assigned_identity" "eso" {
  name                = var.eso_workload_identity_name
  resource_group_name = var.resource_group_name
  location            = var.location
}

# Federated Identity Credential - links K8s Service Account to Azure identity
resource "azurerm_federated_identity_credential" "eso" {
  name                = var.eso_federated_credential_name
  resource_group_name = var.resource_group_name
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.aks.oidc_issuer_url
  parent_id           = azurerm_user_assigned_identity.eso.id
  subject             = "system:serviceaccount:external-secrets-system:eso-workload-identity-sa"
}
