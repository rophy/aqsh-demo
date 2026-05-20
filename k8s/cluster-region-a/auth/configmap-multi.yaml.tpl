apiVersion: v1
kind: ConfigMap
metadata:
  name: kube-federated-auth-config
  namespace: db-ops
data:
  clusters.yaml: |
    authorized_clients:
      - "region-a/db-ops/kube-auth-proxy"
      - "region-b/db-ops/kube-auth-proxy"
    cache:
      ttl: 60
      max_entries: 1000
    clusters:
      region-a:
        issuer: "https://kubernetes.default.svc.cluster.local"
        ca_cert: "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
        token_path: "/var/run/secrets/kubernetes.io/serviceaccount/token"
      region-b:
        issuer: "${ISSUER_REGION_B}"
        api_server: "https://${REGION_B_IP}:6443"
        ca_cert: "/etc/kube-federated-auth/ca-certs/region-b-ca.crt"
        token_path: "/etc/kube-federated-auth/tokens/region-b-token"
      apps-minio:
        issuer: "${ISSUER_APPS_MINIO}"
        api_server: "https://${APPS_MINIO_IP}:6443"
        ca_cert: "/etc/kube-federated-auth/ca-certs/apps-minio-ca.crt"
        token_path: "/etc/kube-federated-auth/tokens/apps-minio-token"
