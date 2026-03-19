variable "resource_group_name" {
  type        = string
  default     = "kml_rg_main-ce8dee9bda7145af"
  description = "Existing Azure resource group name"
}

variable "location" {
  type        = string
  default     = "eastus"
  description = "Azure region"
}

variable "aks_name" {
  type        = string
  default     = "eso-poc-aks"
  description = "Name of the AKS cluster"
}

variable "aks_node_resource_group" {
  type        = string
  default     = null
  description = "Node resource group name. Must be unique in subscription. Default: {aks_name}-nodes. Set to e.g. eso-poc-aks-nodes-001 if previous cluster left orphaned node RG"
}

variable "key_vault_name" {
  type        = string
  description = "Globally unique Key Vault name (3-24 chars, alphanumeric and hyphens; e.g. eso-poc-kv-a1b2c3d4)"
}

variable "key_vault_secret_value" {
  type        = string
  default     = "MySecurePocPassword123"
  sensitive   = true
  description = "Test secret value for database-password in Key Vault"
}

variable "eso_workload_identity_name" {
  type        = string
  default     = "eso-workload-identity"
  description = "Name of the User-Assigned Managed Identity for ESO Workload Identity"
}

variable "eso_federated_credential_name" {
  type        = string
  default     = "eso-external-secrets"
  description = "Name of the Federated Identity Credential linking K8s SA to the ESO Managed Identity"
}
