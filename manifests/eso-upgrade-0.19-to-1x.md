# External Secrets Operator: Upgrade 0.19.2 → 1.x (Azure Key Vault + Workload Identity)

This guide upgrades the **Helm-deployed** External Secrets Operator (ESO) from **0.19.2** to the **latest 1.x** release, then validates **ClusterSecretStore**, **ExternalSecret**, and **sync to Azure Key Vault** using Workload Identity.

> **Target 1.x version (maximum in the 1.x series):** Helm chart **`1.3.2`** (application image **`v1.3.2`**).  
> Verify current chart versions: `helm repo update && helm search repo external-secrets/external-secrets --versions | grep '^external-secrets/external-secrets\s\+1\.'`

---

## 1. Scope and assumptions

| Item | Your POC setup |
|------|----------------|
| Install method | Helm (`external-secrets/external-secrets`) |
| Namespace | `external-secrets-system` |
| Auth to Key Vault | Azure Workload Identity (`authType: WorkloadIdentity`) |
| Values | `tf_code/manifests/eso-workload-identity-values.yaml` |
| CRs | `ClusterSecretStore` + `ExternalSecret` using `external-secrets.io/v1` |

---

## 2. Prerequisites

1. **Kubernetes version**  
   ESO publishes a support matrix per operator version ([Stability and Support](https://external-secrets.io/latest/introduction/stability-support/)). **1.3.x** is listed with **Kubernetes 1.34**. Confirm your AKS control plane meets the version your chosen ESO release expects before upgrading.

2. **Backup / drift awareness**  
   - Export current Helm values:  
     `helm get values external-secrets -n external-secrets-system -o yaml > eso-values-backup.yaml`  
   - Note current chart version:  
     `helm list -n external-secrets-system`  
   - List available chart versions (run after `helm repo update`):  
     `helm search repo external-secrets/external-secrets --versions`

3. **GitOps / stored manifests**  
   If resources were ever applied as `external-secrets.io/v1beta1`, upgrade manifests to **`v1`** *before* moving past 0.16.x (see [§ API versions](#5-apiversion-and-spec-changes-0192-vs-1xx)).

---

## 3. Upgrade (0.19.2 → 1.3.2)

Run the upgrade in one step:

```bash
helm repo add external-secrets https://charts.external-secrets.io 2>/dev/null || true
helm repo update

helm upgrade external-secrets external-secrets/external-secrets \
  --version 1.3.2 \
  --namespace external-secrets-system \
  -f tf_code/manifests/eso-workload-identity-values.yaml
```

**If pods do not pick up Workload Identity labels**, force recreation:

```bash
helm upgrade --install external-secrets external-secrets/external-secrets \
  --version 1.3.2 \
  -n external-secrets-system \
  -f tf_code/manifests/eso-workload-identity-values.yaml \
  --force
```

---

## 4. Helm values and CRDs

- **Keep using** `eso-workload-identity-values.yaml` (`installCRDs: true`, custom SA name, `podLabels` for Workload Identity). Review the chart’s default `values.yaml` for **1.3.2** in case new fields or renamed options affect your deployment (charts are not covered by the same deprecation policy as CRDs).
- **`installCRDs: true`** lets Helm manage CRD updates across upgrades. If you manage CRDs separately, align your process with the chart’s CRD packaging for that version.

---

## 5. `apiVersion` and spec changes (0.19.2 vs 1.x)

### 5.1 `apiVersion` for core resources

| apiVersion | Status |
|------------|--------|
| **`external-secrets.io/v1`** | **Current GA-style API** for `ExternalSecret`, `SecretStore`, `ClusterSecretStore`, `PushSecret`, etc. **Use this for 0.19.2 and 1.x.** |
| `external-secrets.io/v1beta1` | **Removed from serving** starting **0.17.0**. Not applicable if you are already on 0.19.2 with `v1`. |

Your POC templates already use **`external-secrets.io/v1`** (`tf_code/manifests/clustersecretstore.yaml.tpl`, `externalsecret.yaml.tpl`) — **no apiVersion change is required** for this upgrade path.

### 5.2 Azure Key Vault + Workload Identity spec

For a minimal store like yours, the shape remains the familiar **`spec.provider.azurekv`** block:

- `vaultUrl`
- `authType: WorkloadIdentity`
- `serviceAccountRef` (name + namespace for the UAMI/federated SA)

**1.x does not introduce a different apiVersion** for these resources compared to 0.19.x for the standard `v1` CRs. Field-level changes are usually additive (new optional fields). If you use advanced options (e.g. `environmentType`, MSI, custom audiences, `vaultUrl` from other auth types), compare your manifests with the [Azure Key Vault provider](https://external-secrets.io/latest/provider/azure-key-vault/) docs for the **same major doc version** as your operator.

### 5.3 Newer 1.x features (optional)

v1.0.0+ includes enhancements such as **dynamic targets** for syncing to additional object kinds (often behind feature/configuration in Helm). **Standard “sync to Kubernetes `Secret`”** `ExternalSecret` specs like yours are unchanged in intent; you only need to adjust YAML if you opt into those new features.

---

## 6. Post-upgrade verification (Key Vault + Workload Identity)

Run from `tf_code` after the upgrade.

### 6.1 Operator and identity wiring

```bash
kubectl get pods -n external-secrets-system
kubectl get pods -n external-secrets-system -l azure.workload.identity/use=true
kubectl describe pod -n external-secrets-system -l app.kubernetes.io/name=external-secrets | grep -A3 "AZURE_"
```

Expect the controller pod(s) to have Workload Identity env vars and the `azure.workload.identity/use=true` label (from your values).

### 6.2 Store and sync status

```bash
kubectl get clustersecretstore
kubectl describe clustersecretstore azure-store   # Ready: True, no auth errors

kubectl get externalsecret -A
kubectl describe externalsecret database-credentials -n default
```

`ExternalSecret` should show a **Synced** / healthy condition (exact condition text can vary slightly by version).

### 6.3 Target Secret content

```bash
kubectl get secret database-credentials -n default -o jsonpath='{.data.database-password}' | base64 -d
echo
```

Compare with the value in Key Vault (portal or `az keyvault secret show`).

### 6.4 Controller logs (if something fails)

```bash
kubectl logs -n external-secrets-system deploy/external-secrets --tail=200
```

Look for Azure AD / Key Vault permission or federated-credential errors.

---

## 7. Rollback (on failure)

If the upgrade to 1.3.2 fails (pods not ready, Store/ExternalSecret errors, or sync broken), use these steps to return to **0.19.2**.

### 7.1 When to roll back

- Controller pods in `CrashLoopBackOff` or not starting.
- `ClusterSecretStore` stays not Ready or shows auth/Key Vault errors.
- `ExternalSecret` does not reach Synced; target `Secret` missing or stale.
- Workload Identity token/env not present on the ESO pod after upgrade.

### 7.2 Rollback using Helm history (preferred)

1. **List revisions** and identify the last good one (pre–1.3.2):

   ```bash
   helm history external-secrets -n external-secrets-system
   ```

   Note the **REVISION** number of the 0.19.2 release (e.g. `1`).

2. **Roll back** to that revision:

   ```bash
   helm rollback external-secrets <REVISION> -n external-secrets-system
   ```

   Example: `helm rollback external-secrets 1 -n external-secrets-system`

3. **Wait for rollout** and verify pods:

   ```bash
   kubectl rollout status deployment -n external-secrets-system -l app.kubernetes.io/name=external-secrets --timeout=5m
   kubectl get pods -n external-secrets-system -l azure.workload.identity/use=true
   ```

4. **Re-check store and sync** (see [§ 6 Post-upgrade verification](#6-post-upgrade-verification-key-vault--workload-identity)):

   ```bash
   kubectl get clustersecretstore
   kubectl get externalsecret -A
   kubectl get secret database-credentials -n default -o jsonpath='{.data.database-password}' | base64 -d && echo
   ```

### 7.3 Explicit reinstall to 0.19.2 (if rollback is not enough)

If `helm rollback` is unavailable or leaves the release in a bad state, reinstall at 0.19.2 with the same values:

```bash
helm upgrade external-secrets external-secrets/external-secrets \
  --version 0.19.2 \
  --namespace external-secrets-system \
  -f tf_code/manifests/eso-workload-identity-values.yaml
```

If pods still don’t get Workload Identity labels:

```bash
helm upgrade external-secrets external-secrets/external-secrets \
  --version 0.19.2 \
  -n external-secrets-system \
  -f tf_code/manifests/eso-workload-identity-values.yaml \
  --force
```

Then run the same verification commands as in § 7.2 step 4.

### 7.4 CRDs and resource state

- **CRDs:** With `installCRDs: true`, Helm may have upgraded CRDs to 1.x. Rolling back the *release* does **not** downgrade CRDs. In practice, 0.19.2 and 1.x both serve `external-secrets.io/v1`; your existing `ClusterSecretStore` and `ExternalSecret` YAML usually keep working after rollback.
- If you see validation or schema errors on your CRs after rollback, compare with a backup of the CRD manifests or re-apply your store/ExternalSecret manifests. Restoring CRDs to an older version is possible but invasive; only do it if release notes or support channels recommend it.

### 7.5 After a successful rollback

- Re-run the full verification in [§ 6](#6-post-upgrade-verification-key-vault--workload-identity) to confirm secrets are syncing from Key Vault.

---

## 8. Release notes checklist

Before production, skim GitHub releases for each chart you install:

- [Releases · external-secrets/external-secrets](https://github.com/external-secrets/external-secrets/releases)

Pay attention to **BREAKING CHANGE** sections, **Helm** changes, **webhook** / cert changes, and **Kubernetes** minimum version.

---

## 9. After 1.3.2

The project continues with **2.x** (new chart major). The [stability page](https://external-secrets.io/latest/introduction/stability-support/) lists **EOL dates** for 1.x minors; plan a follow-up upgrade to **2.x** for ongoing support — that is a **separate** major migration from this document.

---

## Related docs in this repo

- [eso-setup.md](./eso-setup.md) — initial install and quick 1.3.2 upgrade snippet  
- [workload-identity-explained.md](./workload-identity-explained.md) — data flow and Azure federated credential alignment
