# Copy to terraform.tfvars and customize
# cp terraform.tfvars.example terraform.tfvars

resource_group_name = "kml_rg_main-da4c64bee808497b"
location            = "eastus"
aks_name            = "eso-poc-aks"

# Key Vault name must be globally unique (3-24 chars, alphanumeric and hyphens)
key_vault_name = "eso-poc-kv-a1b2c3d1"

# ESO Workload Identity resource names
eso_workload_identity_name   = "eso-workload-identity"
eso_federated_credential_name = "eso-external-secrets"

# Optional: override the test secret value
# key_vault_secret_value = "MySecurePocPassword123"
