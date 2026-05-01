# db-runbooks

Multi-cluster sandbox for database operations automation with aqsh, kube-auth-proxy, kube-federated-auth, and mariadb-operator across 3 Kind clusters.

## kubectl Contexts

| Context | Cluster | Purpose |
|---------|---------|---------|
| kind-cluster-auth | cluster-auth | kube-federated-auth server |
| kind-cluster-dbs | cluster-dbs | mariadb-operator + aqsh + kube-auth-proxy + Redis |
| kind-cluster-apps | cluster-apps | test-client workload |

Always specify `--context` when running kubectl commands.

## Container Images

- `ghcr.io/rophy/kube-federated-auth:3.2.0`
- `ghcr.io/rophy/kube-auth-proxy:0.4.1`
- `ghcr.io/null-ptr-exception/aqsh:0.4.0`

## Quick Start

```bash
scripts/setup.sh    # Create clusters, deploy, test
scripts/teardown.sh # Clean up everything
```
