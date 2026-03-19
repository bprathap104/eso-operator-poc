apiVersion: v1
kind: ServiceAccount
metadata:
  name: eso-workload-identity-sa
  namespace: external-secrets-system
  annotations:
    azure.workload.identity/client-id: "CLIENT_ID"
    azure.workload.identity/tenant-id: "TENANT_ID"
