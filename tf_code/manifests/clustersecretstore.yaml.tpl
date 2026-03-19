apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: azure-store
spec:
  provider:
    azurekv:
      vaultUrl: "VAULT_URI"
      authType: WorkloadIdentity
      serviceAccountRef:
        name: eso-workload-identity-sa
        namespace: external-secrets-system
