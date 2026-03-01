# aqsh-demo

Multi-cluster sandbox demonstrating aqsh + kube-auth-proxy + kube-federated-auth across 3 Kind clusters.

## kubectl Contexts

| Context | Cluster | Purpose |
|---------|---------|---------|
| kind-cluster-a | cluster-a | kube-federated-auth server |
| kind-cluster-b | cluster-b | aqsh + kube-auth-proxy + Redis |
| kind-cluster-c | cluster-c | test-client workload |

Always specify `--context` when running kubectl commands.

## Container Images

- `ghcr.io/rophy/kube-federated-auth:3.2.0`
- `ghcr.io/rophy/kube-auth-proxy:0.4.1`
- `ghcr.io/rophy/aqsh:0.3.1`

## Quick Start

```bash
scripts/setup.sh    # Create clusters, deploy, test
scripts/teardown.sh # Clean up everything
```
