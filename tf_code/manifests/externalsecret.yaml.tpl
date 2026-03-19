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
