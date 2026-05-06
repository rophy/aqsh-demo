# db-runbooks

A multi-cluster sandbox for database operations automation. Uses [aqsh](https://github.com/null-ptr-exception/aqsh) to execute runbook tasks against databases, with cross-cluster authentication via [kube-auth-proxy](https://github.com/rophy/kube-auth-proxy) and [kube-federated-auth](https://github.com/rophy/kube-federated-auth).

## Overview

A test-client in **cluster-apps** submits tasks to aqsh in **cluster-dbs**, authenticating with its own Kubernetes ServiceAccount token. The token is validated across clusters via kube-federated-auth in **cluster-auth**.

```
cluster-apps                 cluster-dbs                     cluster-auth
┌──────────────┐            ┌────────────────────────┐      ┌──────────────────────┐
│ test-client  │───Bearer──▶│ kube-auth-proxy :4180  │─────▶│ kube-federated-auth  │
│ (SA token)   │   token    │   ├─▶ aqsh :8080       │ Token│   ├─ cluster-auth     │
└──────────────┘            │   ├─▶ Redis            │Review│   │   (local)         │
                            │   └─▶ MariaDB          │      │   ├─ cluster-dbs ───┐│
                            └────────────────────────┘      │   └─ cluster-apps ──┼┤
                                                            └─────────────────────┼┼┘
                            cluster-dbs API :6443 ◀───────────────────────────────┘│
                            cluster-apps API :6443 ◀───────────────────────────────┘
```

## Components

| Cluster | Component | Role |
|---------|-----------|------|
| cluster-auth | [kube-federated-auth](https://github.com/rophy/kube-federated-auth) | Validates SA tokens from all 3 clusters via JWKS detection + TokenReview forwarding |
| cluster-dbs | [aqsh](https://github.com/null-ptr-exception/aqsh) | Async task queue — executes runbook scripts submitted via REST API |
| cluster-dbs | [kube-auth-proxy](https://github.com/rophy/kube-auth-proxy) | Sidecar that authenticates requests and sets identity headers for aqsh |
| cluster-dbs | Redis | Message broker for aqsh task queue |
| cluster-dbs | MariaDB (via mariadb-operator) | Database instance managed by the operator |
| cluster-apps | test-client | Pod (curlimages/curl) that sends authenticated requests to aqsh |

## Request Flow

1. **test-client** (cluster-apps) sends `POST /tasks/hello` with its SA token as Bearer
2. **kube-auth-proxy** (cluster-dbs) intercepts the request and sends a TokenReview to kube-federated-auth, authenticating itself with its own SA token
3. **kube-federated-auth** (cluster-auth) validates the caller (kube-auth-proxy) against `authorized_clients`, detects the subject token belongs to cluster-apps via JWKS, and forwards the TokenReview to cluster-apps's API server
4. **kube-auth-proxy** receives the authenticated identity, sets `X-Forwarded-User` / `X-Forwarded-Groups` / `X-Forwarded-Extra-Cluster-Name` headers, strips `Authorization`, and proxies to aqsh
5. **aqsh** checks `allowed_groups` / `allowed_users`, accepts the task, and executes the script

## Namespaces

| Namespace | Clusters | Purpose |
|-----------|----------|---------|
| `db-ops` | cluster-auth, cluster-dbs, cluster-apps | Control plane — federated auth, aqsh task runner, cross-cluster credentials |
| `db-1`, `db-2`, `db-3` | cluster-dbs | MariaDB instances (10.6, 10.11, 11.4) |
| `app-a`, `app-b` | cluster-apps | Per-application client workloads |

Authorization is configured in aqsh task definitions: each app's ServiceAccount (`app-a/test-client`, `app-b/test-client`) is granted access to specific tasks via `allowed_users`, enforcing which app can operate on which database.

## Cross-Cluster Networking

Kind clusters share the `kind` Docker bridge network. All cluster nodes are Docker containers with directly reachable IPs. Services are exposed via NodePort:

| Service | Cluster | NodePort |
|---------|---------|----------|
| kube-federated-auth | cluster-auth | 30080 |
| aqsh (via kube-auth-proxy) | cluster-dbs | 30081 |

Pods in any cluster can reach services in other clusters at `<node-docker-ip>:<nodeport>`.

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/)
- [kind](https://kind.sigs.k8s.io/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Helm](https://helm.sh/)
- [Skaffold](https://skaffold.dev/)
- [jq](https://jqlang.github.io/jq/)
- curl

## Quick Start

```bash
# Create clusters, deploy everything, and run tests
./scripts/setup.sh

# Or step by step:
./scripts/setup-clusters.sh      # Create 3 Kind clusters
./scripts/deploy.sh              # Deploy all components
./scripts/test.sh                # Run end-to-end tests
```

## Development

Task scripts live in `aqsh-tasks/scripts/`. To iterate on tasks:

```bash
# Build and load into Kind cluster
skaffold build --tag=latest
kind load docker-image aqsh-tasks:latest --name cluster-dbs
kubectl --context kind-cluster-dbs -n db-ops rollout restart deployment/aqsh
```

## Teardown

```bash
./scripts/teardown.sh
```

## Project Structure

```
aqsh-tasks/
  Dockerfile                # Custom image: aqsh base + task scripts
  tasks.yaml                # Task definitions (hello, restart)
  scripts/
    hello.sh                # Simple greeting task
    restart.sh              # Rolling restart of MariaDB StatefulSet

scripts/
  setup.sh                  # Orchestrator
  setup-clusters.sh         # Create Kind clusters, extract IPs → .env
  setup-credentials.sh      # Bootstrap cross-cluster CA certs + tokens
  deploy.sh                 # Build image + deploy manifests in dependency order
  test.sh                   # End-to-end validation
  teardown.sh               # Delete clusters

k8s/
  cluster-auth/             # kube-federated-auth manifests
  cluster-dbs/              # aqsh + kube-auth-proxy + Redis + MariaDB manifests
  cluster-apps/             # test-client manifests
```

## Image Versions

| Image | Version |
|-------|---------|
| ghcr.io/rophy/kube-federated-auth | 3.2.0 |
| ghcr.io/rophy/kube-auth-proxy | 0.4.1 |
| ghcr.io/null-ptr-exception/aqsh | 0.4.0 |
| aqsh-tasks | local build (Skaffold) |
| mariadb-operator (Helm) | latest |
| mariadb | 10.6, 10.11, 11.4 |
| redis | 7-alpine |
