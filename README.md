# aqsh-demo

A multi-cluster sandbox demonstrating cross-cluster workload authentication with [aqsh](https://github.com/rophy/aqsh), [kube-auth-proxy](https://github.com/rophy/kube-auth-proxy), and [kube-federated-auth](https://github.com/rophy/kube-federated-auth).

## Overview

A test-client in **cluster-c** submits tasks to aqsh in **cluster-b**, authenticating with its own Kubernetes ServiceAccount token. The token is validated across clusters via kube-federated-auth in **cluster-a**.

```
cluster-c                    cluster-b                       cluster-a
┌──────────────┐            ┌────────────────────────┐      ┌──────────────────────┐
│ test-client  │───Bearer──▶│ kube-auth-proxy :4180  │─────▶│ kube-federated-auth  │
│ (SA token)   │   token    │   ├─▶ aqsh :8080       │ Token│   ├─ cluster-a (local)│
└──────────────┘            │   └─▶ Redis             │Review│   ├─ cluster-b ──────┐│
                            └────────────────────────┘      │   └─ cluster-c ───┐  ││
                                                            └───────────────────┼──┼┘
                            cluster-b API :6443 ◀───────────────────────────────┘  │
                            cluster-c API :6443 ◀──────────────────────────────────┘
```

## Components

| Cluster | Component | Role |
|---------|-----------|------|
| cluster-a | [kube-federated-auth](https://github.com/rophy/kube-federated-auth) | Validates SA tokens from all 3 clusters via JWKS detection + TokenReview forwarding |
| cluster-b | [aqsh](https://github.com/rophy/aqsh) | Async task queue — executes shell scripts submitted via REST API |
| cluster-b | [kube-auth-proxy](https://github.com/rophy/kube-auth-proxy) | Sidecar that authenticates requests and sets identity headers for aqsh |
| cluster-b | Redis | Message broker for aqsh task queue |
| cluster-c | test-client | Alpine pod with curl/jq that sends authenticated requests to aqsh |

## Request Flow

1. **test-client** (cluster-c) sends `POST /tasks/hello` with its SA token as Bearer
2. **kube-auth-proxy** (cluster-b) intercepts the request and sends a TokenReview to kube-federated-auth, authenticating itself with its own SA token
3. **kube-federated-auth** (cluster-a) validates the caller (kube-auth-proxy) against `authorized_clients`, detects the subject token belongs to cluster-c via JWKS, and forwards the TokenReview to cluster-c's API server
4. **kube-auth-proxy** receives the authenticated identity, sets `X-Forwarded-User` / `X-Forwarded-Groups` / `X-Forwarded-Extra-Cluster-Name` headers, strips `Authorization`, and proxies to aqsh
5. **aqsh** checks `allowed_groups`, accepts the task, and executes the script

## Cross-Cluster Networking

Kind clusters share the `kind` Docker bridge network. All cluster nodes are Docker containers with directly reachable IPs. Services are exposed via NodePort:

| Service | Cluster | NodePort |
|---------|---------|----------|
| kube-federated-auth | cluster-a | 30080 |
| aqsh (via kube-auth-proxy) | cluster-b | 30081 |

Pods in any cluster can reach services in other clusters at `<node-docker-ip>:<nodeport>`.

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/)
- [kind](https://kind.sigs.k8s.io/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
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

## Teardown

```bash
./scripts/teardown.sh
```

## Project Structure

```
scripts/
  setup.sh                  # Orchestrator
  setup-clusters.sh         # Create Kind clusters, extract IPs → .env
  setup-credentials.sh      # Bootstrap cross-cluster CA certs + tokens
  deploy.sh                 # Deploy manifests in dependency order
  test.sh                   # End-to-end validation
  teardown.sh               # Delete clusters

k8s/
  cluster-a/                # kube-federated-auth manifests
  cluster-b/                # aqsh + kube-auth-proxy + Redis manifests
  cluster-c/                # test-client manifests
```

## Image Versions

| Image | Version |
|-------|---------|
| ghcr.io/rophy/kube-federated-auth | 3.2.0 |
| ghcr.io/rophy/kube-auth-proxy | 0.4.1 |
| ghcr.io/rophy/aqsh | 0.3.1 |
| redis | 7-alpine |
