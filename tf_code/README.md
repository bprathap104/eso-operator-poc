# ESO + Azure Key Vault + AKS - Terraform IaC

Terraform provisions **AKS, Key Vault, and Workload Identity** for ESO. ESO Helm, ClusterSecretStore, and ExternalSecret are installed manually via command line.

**Notes:** Uses Access Policy (not RBAC) for Key Vault. AKS uses Standard_D2s_v3, 2 nodes. **Workload Identity** is used for ESO authentication (no Service Principal/Client Secret).

## Prerequisites

- Terraform >= 1.0
- Azure CLI (`az`) - authenticate with `az login`
- Existing resource group: `kml_rg_main-ce8dee9bda7145af`

## Step 1: Terraform (AKS + Key Vault)

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars:
#   - key_vault_name (required)

terraform init
terraform plan
terraform apply
```

Terraform creates: AKS cluster, Key Vault, `database-password` secret, User-Assigned Managed Identity, and Federated Identity Credential.

## Step 2: Connect to AKS

```bash
az aks get-credentials --resource-group $(terraform output -raw resource_group_name) --name $(terraform output -raw aks_name)
kubectl get nodes
```

## Step 3: Install External Secrets Operator (Helm)

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo update
helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets-system \
  --create-namespace \
  --set installCRDs=true

kubectl get pods -n external-secrets-system
```

## Step 4: Apply ClusterSecretStore and ExternalSecret

```bash
# Create Workload Identity Service Account
kubectl create namespace external-secrets-system --dry-run=client -o yaml | kubectl apply -f -

export TENANT_ID=$(terraform output -raw tenant_id)
export CLIENT_ID=$(terraform output -raw eso_client_id)

sed -e "s|TENANT_ID|$TENANT_ID|g" -e "s|CLIENT_ID|$CLIENT_ID|g" manifests/workload-identity-sa.yaml.tpl | kubectl apply -f -

# Reinstall ESO with Workload Identity SA and pod label (required for Azure token injection)
helm upgrade --install external-secrets external-secrets/external-secrets \
  --namespace external-secrets-system \
  --create-namespace \
  -f manifests/eso-workload-identity-values.yaml

# Apply ClusterSecretStore and ExternalSecret
export VAULT_URI=$(terraform output -raw vault_uri)
sed -e "s|TENANT_ID|$TENANT_ID|g" -e "s|VAULT_URI|$VAULT_URI|g" manifests/clustersecretstore.yaml.tpl | kubectl apply -f -
kubectl apply -f manifests/externalsecret.yaml.tpl
```

## Step 5: Validate

```bash
kubectl get clustersecretstore
kubectl get externalsecret -A
kubectl get secret database-credentials -n default -o jsonpath='{.data.database-password}' | base64 -d
```

## Resources


| Created by | Resource                                                                     |
| ---------- | ---------------------------------------------------------------------------- |
| Terraform  | AKS cluster, Key Vault, Key Vault secret, Managed Identity, Federated Credential |
| Helm       | External Secrets Operator                                                    |
| kubectl    | Workload Identity SA, ClusterSecretStore, ExternalSecret                    |


## Variables


| Variable               | Description                    | Default                       |
| ---------------------- | ------------------------------ | ----------------------------- |
| resource_group_name   | Existing Azure resource group  | kml_rg_main-ce8dee9bda7145af |
| location               | Azure region                   | eastus                        |
| aks_name               | AKS cluster name               | eso-poc-aks                   |
| key_vault_name         | Globally unique Key Vault name | (required)                    |
| key_vault_secret_value | Test secret value              | MySecurePocPassword123       |


