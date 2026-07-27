# Proxyless gRPC Service Mesh on GCP — Home Assignment

Senior DevOps Engineer hands-on assignment: analysis of gRPC load-balancing
issues and a working proxyless gRPC mesh on Google Cloud Service Mesh,
deployed with Terraform + Argo CD.

## Deliverables map

| Assignment item | Location |
|---|---|
| Task 1 — gRPC/HTTP2/DNS load-balancing analysis | [WRITEUP.md](WRITEUP.md) |
| Task 2 — solutions comparison, GCP best-fit, proxyless (Go), references | [WRITEUP.md](WRITEUP.md) |
| Task 3 — IaC for the GCP environment (Terraform) | [grpc-mesh-infra/terraform/](grpc-mesh-infra/terraform/) |
| Task 4 — `server.go` (SayHello, xDS, :50051) | [grpc-hello-app/cmd/server/server.go](grpc-hello-app/cmd/server/server.go) |
| Task 5 — `client.go` (xds:/// target, SayHello) | [grpc-hello-app/cmd/client/client.go](grpc-hello-app/cmd/client/client.go) |
| Dockerfile | [grpc-hello-app/Dockerfile](grpc-hello-app/Dockerfile) |
| Task 6 — ArgoCD GitOps deployment | [grpc-mesh-infra/argocd/](grpc-mesh-infra/argocd/) + [grpc-mesh-infra/k8s/](grpc-mesh-infra/k8s/) |
| Evidence — screenshots | [docs/evidence.md](docs/evidence.md) |
| Docs — runbook, architecture, troubleshooting | [docs/](docs/) |

The two top-level directories are intended to be published as **two separate
Git repositories** (application repo and GitOps/IaC repo), matching the
assignment's repository requirements.

## Architecture

![Architecture diagram](assets/architecture.svg)

## TL;DR of the design

* **Problem:** gRPC = HTTP/2 = one long-lived multiplexed connection; DNS is
  resolved once and kube-proxy balances per *connection*, so all RPCs pin to
  one pod, scaling adds capacity that receives zero traffic, and rollouts
  cause reconnect storms. HTTP/1.1 escapes this only because it opens
  connections constantly (one request in flight per connection).
* **Solution deployed here:** Google **Cloud Service Mesh, proxyless** — the
  grpc-go library is itself the xDS client. `Mesh` + `GRPCRoute` +
  `INTERNAL_SELF_MANAGED`/`GRPC` backend service + standalone zonal NEGs give
  per-RPC load balancing directly to pod IPs, with Google operating the
  control plane and **no sidecars**.
* **Delivery:** Terraform builds VPC, GKE (Workload Identity), IAM
  (`roles/trafficdirector.client`), Artifact Registry, the mesh resources and
  Argo CD; Argo CD owns all Kubernetes manifests (automated sync + prune +
  self-heal).

## Quick start

Follow the runbook in [grpc-mesh-infra/README.md](grpc-mesh-infra/README.md).
