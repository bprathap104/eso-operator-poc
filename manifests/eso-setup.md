# ESO Setup (Workload Identity)

Run these commands from the `tf_code` directory.

**Migration test:** Install ESO 0.19.2 first, then upgrade to 1.3.2 to validate the migration path.

**Full upgrade guide (API differences, stepped path, verification):** [eso-upgrade-0.19-to-1x.md](./eso-upgrade-0.19-to-1x.md).

## 1. Connect to AKS

```bash
cd tf_code
az aks get-credentials --resource-group $(terraform output -raw resource_group_name) --name $(terraform output -raw aks_name)
kubectl get nodes
```

## 2. Configure Workload Identity (before install)

Create the namespace and Service Account first so ESO can use them from the start:

```bash
kubectl create namespace external-secrets-system --dry-run=client -o yaml | kubectl apply -f -

export TENANT_ID=$(terraform output -raw tenant_id)
export CLIENT_ID=$(terraform output -raw eso_client_id)

sed -e "s|TENANT_ID|$TENANT_ID|g" -e "s|CLIENT_ID|$CLIENT_ID|g" manifests/workload-identity-sa.yaml.tpl | kubectl apply -f -
```

## 3. Install External Secrets Operator (v0.19.2)

Install with the Workload Identity values file so `podLabels` and Service Account are applied from the start:

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo update
helm install external-secrets external-secrets/external-secrets \
  --version 0.19.2 \
  --namespace external-secrets-system \
  --create-namespace \
  -f manifests/eso-workload-identity-values.yaml

kubectl get pods -n external-secrets-system -w
# Wait until all pods are Running, then Ctrl+C
```

**Verify podLabels:** `kubectl get pods -n external-secrets-system -l azure.workload.identity/use=true` should list the controller pod. If not, re-run the install with `--force` to recreate pods: `helm upgrade --install external-secrets external-secrets/external-secrets --version 0.19.2 -n external-secrets-system -f manifests/eso-workload-identity-values.yaml --force`

## 4. Apply ClusterSecretStore and ExternalSecret

```bash
export TENANT_ID=$(terraform output -raw tenant_id)
export VAULT_URI=$(terraform output -raw vault_uri)

sed -e "s|TENANT_ID|$TENANT_ID|g" -e "s|VAULT_URI|$VAULT_URI|g" manifests/clustersecretstore.yaml.tpl | kubectl apply -f -

kubectl apply -f manifests/externalsecret.yaml.tpl
```

## 5. Verify

```bash
kubectl get clustersecretstore
# Should show azure-store with Ready: True

kubectl get externalsecret -A
# Should show database-credentials with SecretSynced

kubectl get secret database-credentials -n default -o jsonpath='{.data.database-password}' | base64 -d
# Should print the secret value
```

## 6. Migrate to ESO 1.3.2

After verifying 0.19.2 works, upgrade to 1.3.2:

```bash
helm upgrade external-secrets external-secrets/external-secrets \
  --version 1.3.2 \
  --namespace external-secrets-system \
  -f manifests/eso-workload-identity-values.yaml

kubectl get pods -n external-secrets-system -w
# Wait until all pods are Running, then Ctrl+C

# Re-verify secrets still sync
kubectl get clustersecretstore
kubectl get externalsecret -A
kubectl get secret database-credentials -n default -o jsonpath='{.data.database-password}' | base64 -d
```
