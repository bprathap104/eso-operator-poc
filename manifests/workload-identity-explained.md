# How ESO + Azure Workload Identity Works

This document explains every configuration data point required for External Secrets Operator (ESO) to sync Azure Key Vault secrets into Kubernetes using **Workload Identity** (federated credentials, no client secrets).

## Architecture Overview

```
┌──────────────────────────────────────────────────────────────────────┐
│  Azure                                                               │
│                                                                      │
│  ┌─────────────────────┐      ┌──────────────────────────────────┐  │
│  │  Key Vault           │      │  User-Assigned Managed Identity  │  │
│  │  - database-password │◄─────│  (eso-workload-identity)         │  │
│  │                      │ Get/ │                                  │  │
│  │                      │ List │  Access Policy: Get, List        │  │
│  └─────────────────────┘      │                                  │  │
│                                │  ┌────────────────────────────┐ │  │
│                                │  │ Federated Identity         │ │  │
│                                │  │ Credential                 │ │  │
│                                │  │                            │ │  │
│                                │  │ issuer: AKS OIDC URL       │ │  │
│                                │  │ subject: system:service    │ │  │
│                                │  │   account:external-secrets │ │  │
│                                │  │   -system:eso-workload-    │ │  │
│                                │  │   identity-sa              │ │  │
│                                │  └────────────────────────────┘ │  │
│                                └──────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────┘
        ▲                                    ▲
        │ Reads secrets                      │ Token exchange
        │                                    │ (OIDC → Azure AD)
┌───────┼────────────────────────────────────┼─────────────────────────┐
│  AKS Cluster (oidc + workload identity enabled)                      │
│       │                                    │                         │
│  ┌────┴──────────────────────────────────────────────────────────┐   │
│  │  ESO Controller Pod                                           │   │
│  │                                                               │   │
│  │  Label: azure.workload.identity/use: "true"                   │   │
│  │  Service Account: eso-workload-identity-sa                    │   │
│  │                                                               │   │
│  │  Injected by WI webhook:                                      │   │
│  │    - AZURE_CLIENT_ID      (from SA annotation)                │   │
│  │    - AZURE_TENANT_ID      (from SA annotation)                │   │
│  │    - AZURE_FEDERATED_TOKEN_FILE = /var/run/secrets/...        │   │
│  │    - Volume mount: projected service account token            │   │
│  └───────────────────────────────────────────────────────────────┘   │
│                                                                      │
│  ┌───────────────────┐     ┌──────────────────────────────────────┐  │
│  │  ClusterSecretStore│────▶│  ExternalSecret                     │  │
│  │  (azure-store)     │     │  (database-credentials)             │  │
│  │  authType:         │     │                                     │  │
│  │   WorkloadIdentity │     │  Syncs Key Vault secret ──▶         │  │
│  │  serviceAccountRef:│     │  K8s Secret (database-credentials)  │  │
│  │   eso-workload-    │     └──────────────────────────────────────┘  │
│  │   identity-sa      │                                              │
│  └───────────────────┘                                               │
└──────────────────────────────────────────────────────────────────────┘
```

## Configuration Data Points

### 1. AKS Cluster

Both settings must be `true` for the cluster to issue OIDC tokens and run the Workload Identity webhook.

| Setting                     | Value  | Purpose                                                       |
| --------------------------- | ------ | ------------------------------------------------------------- |
| `oidc_issuer_enabled`       | `true` | Exposes an OIDC issuer URL that Azure AD trusts for token exchange |
| `workload_identity_enabled` | `true` | Deploys the mutating admission webhook that injects tokens into pods |

**Terraform** (`aks.tf`):
```hcl
oidc_issuer_enabled       = true
workload_identity_enabled = true
```

**Verify:**
```bash
az aks show -g <rg> -n <aks> --query "{oidc: oidcIssuerProfile.enabled, wi: securityProfile.workloadIdentity.enabled}"
```

### 2. User-Assigned Managed Identity

A dedicated Azure identity for ESO. Has no client secret — authentication is done via federated token exchange.

| Property       | Usage                                                       |
| -------------- | ----------------------------------------------------------- |
| `client_id`    | Goes into the K8s Service Account annotation                |
| `principal_id` | Used in the Key Vault Access Policy to grant secret access  |

**Terraform** (`workload_identity.tf`):
```hcl
resource "azurerm_user_assigned_identity" "eso" {
  name                = var.eso_workload_identity_name
  resource_group_name = var.resource_group_name
  location            = var.location
}
```

### 3. Federated Identity Credential

The trust link between Azure AD and the Kubernetes Service Account. Azure AD will accept OIDC tokens from the AKS cluster's issuer for the specific Service Account.

| Property   | Value                                  | Purpose                                      |
| ---------- | -------------------------------------- | -------------------------------------------- |
| `issuer`   | AKS OIDC issuer URL                   | Azure AD trusts tokens from this issuer      |
| `subject`  | `system:serviceaccount:external-secrets-system:eso-workload-identity-sa` | Exact K8s SA identity that can use this credential |
| `audience` | `api://AzureADTokenExchange`           | Standard audience for Azure WI token exchange |
| `parent_id`| Managed Identity resource ID           | The Azure identity this credential belongs to |

**Terraform** (`workload_identity.tf`):
```hcl
resource "azurerm_federated_identity_credential" "eso" {
  name                = var.eso_federated_credential_name
  resource_group_name = var.resource_group_name
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.aks.oidc_issuer_url
  subject             = "system:serviceaccount:external-secrets-system:eso-workload-identity-sa"
  parent_id           = azurerm_user_assigned_identity.eso.id
}
```

> **Critical:** The `subject` must match the Service Account name and namespace exactly. A mismatch means Azure AD will reject the token.

### 4. Key Vault Access Policy

Grants the Managed Identity `Get` and `List` permissions on Key Vault secrets. Uses the identity's `principal_id` (Object ID).

**Terraform** (`keyvault.tf`):
```hcl
resource "azurerm_key_vault_access_policy" "eso" {
  key_vault_id = azurerm_key_vault.kv.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_user_assigned_identity.eso.principal_id
  secret_permissions = ["Get", "List"]
}
```

### 5. Kubernetes Service Account

The bridge on the K8s side. Annotations tell the Workload Identity webhook which Azure identity to use.

| Annotation                            | Value                             | Purpose                                              |
| ------------------------------------- | --------------------------------- | ---------------------------------------------------- |
| `azure.workload.identity/client-id`   | Managed Identity's `client_id`    | Webhook injects this as `AZURE_CLIENT_ID` env var    |
| `azure.workload.identity/tenant-id`   | Azure tenant ID                   | Webhook injects this as `AZURE_TENANT_ID` env var    |

**Manifest** (`workload-identity-sa.yaml.tpl`):
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: eso-workload-identity-sa
  namespace: external-secrets-system
  annotations:
    azure.workload.identity/client-id: "<CLIENT_ID>"
    azure.workload.identity/tenant-id: "<TENANT_ID>"
```

### 6. ESO Pod Label

The Workload Identity mutating webhook **only injects tokens into pods that have this label**. Without it, the pod gets no Azure credentials.

| Label                             | Value    | Purpose                                    |
| --------------------------------- | -------- | ------------------------------------------ |
| `azure.workload.identity/use`     | `"true"` | Triggers the WI webhook to inject credentials |

**Helm values** (`eso-workload-identity-values.yaml`):
```yaml
serviceAccount:
  create: false
  name: eso-workload-identity-sa
podLabels:
  "azure.workload.identity/use": "true"
```

**What the webhook injects into the ESO controller pod:**
- `AZURE_CLIENT_ID` env var (from SA annotation)
- `AZURE_TENANT_ID` env var (from SA annotation)
- `AZURE_FEDERATED_TOKEN_FILE` env var (path to projected token)
- A projected volume mounting the OIDC service account token

**Verify:**
```bash
kubectl get pods -n external-secrets-system -l azure.workload.identity/use=true
kubectl describe pod -n external-secrets-system -l app.kubernetes.io/name=external-secrets | grep -A2 "AZURE_"
```

### 7. ClusterSecretStore

Tells ESO to use Workload Identity auth and which Service Account to use for token exchange.

| Field                | Value                            | Purpose                                |
| -------------------- | -------------------------------- | -------------------------------------- |
| `authType`           | `WorkloadIdentity`               | Use federated token (not client secret) |
| `vaultUrl`           | Key Vault URI                    | Which Key Vault to read from           |
| `serviceAccountRef`  | `eso-workload-identity-sa` in `external-secrets-system` | SA whose token ESO uses for auth |

**Manifest** (`clustersecretstore.yaml.tpl`):
```yaml
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: azure-store
spec:
  provider:
    azurekv:
      vaultUrl: "<VAULT_URI>"
      authType: WorkloadIdentity
      serviceAccountRef:
        name: eso-workload-identity-sa
        namespace: external-secrets-system
```

> **Note:** Do not set `tenantId` here when the Service Account already has the `azure.workload.identity/tenant-id` annotation. ESO rejects duplicate tenant IDs from multiple sources.

### 8. ExternalSecret

Defines which Key Vault secrets to sync and where to store them in Kubernetes.

**Manifest** (`externalsecret.yaml.tpl`):
```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: database-credentials
  namespace: default
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: ClusterSecretStore
    name: azure-store
  target:
    name: database-credentials
    creationPolicy: Owner
  data:
    - secretKey: database-password
      remoteRef:
        key: secret/database-password
```

## Token Exchange Flow

When the ESO controller pod starts and attempts to read a Key Vault secret, this is the authentication flow:

1. **Pod starts** with `azure.workload.identity/use: "true"` label
2. **WI webhook intercepts** pod creation and injects:
   - Projected service account token volume (OIDC JWT signed by the AKS OIDC issuer)
   - `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_FEDERATED_TOKEN_FILE` env vars
3. **ESO reads** the projected token from `AZURE_FEDERATED_TOKEN_FILE`
4. **ESO sends** the token to Azure AD: "I am `system:serviceaccount:external-secrets-system:eso-workload-identity-sa` from this AKS cluster, exchange this for an Azure token for client `<CLIENT_ID>`"
5. **Azure AD validates**:
   - The OIDC token's issuer matches the Federated Identity Credential's `issuer`
   - The token's subject matches the Federated Identity Credential's `subject`
   - The audience matches `api://AzureADTokenExchange`
6. **Azure AD returns** an access token for the Managed Identity
7. **ESO uses** this token to call Key Vault and retrieve secrets
8. **ESO creates/updates** the Kubernetes Secret with the retrieved values

## Verification Commands

```bash
# AKS: OIDC and Workload Identity enabled
az aks show -g <rg> -n <aks> --query "{oidc: oidcIssuerProfile.enabled, wi: securityProfile.workloadIdentity.enabled}"

# Pod has the WI label
kubectl get pods -n external-secrets-system -l azure.workload.identity/use=true

# Pod has injected env vars
kubectl describe pod -n external-secrets-system -l app.kubernetes.io/name=external-secrets | grep -A2 "AZURE_"

# Service Account annotations
kubectl get sa eso-workload-identity-sa -n external-secrets-system -o yaml

# ClusterSecretStore is Ready
kubectl get clustersecretstore azure-store

# ExternalSecret is synced
kubectl get externalsecret -A

# Secret value matches Key Vault
kubectl get secret database-credentials -n default -o jsonpath='{.data.database-password}' | base64 -d
```
