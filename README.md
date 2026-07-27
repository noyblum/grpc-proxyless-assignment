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
| Task 4 — `server.go` (SayHello, xDS, :50051) | [grpc-hello-app · cmd/server/server.go](https://github.com/noyblum/grpc-hello-app/blob/main/cmd/server/server.go) |
| Task 5 — `client.go` (xds:/// target, SayHello) | [grpc-hello-app · cmd/client/client.go](https://github.com/noyblum/grpc-hello-app/blob/main/cmd/client/client.go) |
| Dockerfile | [grpc-hello-app · Dockerfile](https://github.com/noyblum/grpc-hello-app/blob/main/Dockerfile) |
| Task 6 — ArgoCD GitOps deployment | [grpc-mesh-infra/argocd/](grpc-mesh-infra/argocd/) + [grpc-mesh-infra/k8s/](grpc-mesh-infra/k8s/) |
| Evidence — screenshots | [docs/evidence.md](docs/evidence.md) |
| Docs — runbook, architecture, troubleshooting | [docs/](docs/) |

Per the assignment's repository requirements this project is split into two
repositories:

* **Application repo:** [noyblum/grpc-hello-app](https://github.com/noyblum/grpc-hello-app) — Go source, proto, Dockerfile.
* **GitOps/IaC repo (this one):** Terraform, Kubernetes manifests, Argo CD
  application, write-up and docs.

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
