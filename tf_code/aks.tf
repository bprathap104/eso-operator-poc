# Policy-compliant: Standard_D2s_v3, 2 nodes
# Workload Identity enabled for ESO federated identity
resource "azurerm_kubernetes_cluster" "aks" {
  name                = var.aks_name
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = var.aks_name
  node_resource_group = coalesce(var.aks_node_resource_group, "${var.aks_name}-nodes")

  oidc_issuer_enabled     = true
  workload_identity_enabled = true

  default_node_pool {
    name       = "default"
    node_count = 2
    vm_size    = "Standard_D2s_v3"
  }

  identity {
    type = "SystemAssigned"
  }
}