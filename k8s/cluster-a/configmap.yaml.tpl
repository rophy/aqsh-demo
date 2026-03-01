apiVersion: v1
kind: ConfigMap
metadata:
  name: kube-federated-auth-config
  namespace: aqsh-demo
data:
  clusters.yaml: |
    authorized_clients:
      - "cluster-b/aqsh-demo/kube-auth-proxy"
    cache:
      ttl: 60
      max_entries: 1000
    clusters:
      cluster-a:
        issuer: "https://kubernetes.default.svc.cluster.local"
        ca_cert: "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
        token_path: "/var/run/secrets/kubernetes.io/serviceaccount/token"
      cluster-b:
        issuer: "${ISSUER_B}"
        api_server: "https://${CLUSTER_B_IP}:6443"
        ca_cert: "/etc/kube-federated-auth/ca-certs/cluster-b-ca.crt"
        token_path: "/etc/kube-federated-auth/tokens/cluster-b-token"
      cluster-c:
        issuer: "${ISSUER_C}"
        api_server: "https://${CLUSTER_C_IP}:6443"
        ca_cert: "/etc/kube-federated-auth/ca-certs/cluster-c-ca.crt"
        token_path: "/etc/kube-federated-auth/tokens/cluster-c-token"
