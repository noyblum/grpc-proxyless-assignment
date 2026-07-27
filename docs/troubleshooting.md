# Troubleshooting log

Real issues hit while deploying this assignment, in order, with the diagnosis
path. Kept as documentation because the debugging is at least as instructive
as the happy path.

## 1. GKE nodes never came up - `GCE_STOCKOUT`

**Symptom:** `terraform apply` stuck on `google_container_cluster: Still creating... [35m]`,
then failed.

**Diagnosis:** terraform's "Still creating" is just a polling loop. The real
error lives in the GKE operations log:

```bash
gcloud container operations list --region us-central1
# [GCE_STOCKOUT]: The zone 'us-central1-b' does not have enough resources...
```

Zones `us-central1-b`, `-f`, and later `-c` all had no e2 capacity (common for
new/trial projects at peak hours).

**Fix:** pin `node_locations` explicitly instead of letting a regional cluster
spread across all zones; progressively narrowed to `us-central1-a`, the one
zone with capacity. Replaced the half-created cluster with
`terraform apply -replace=google_container_cluster.mesh`.

**Code change** (`grpc-mesh-infra/terraform/gke.tf` + `variables.tf`):

Before - a regional cluster with no `node_locations` schedules nodes in every
zone of the region, including stocked-out ones:

```hcl
resource "google_container_cluster" "mesh" {
  name     = var.cluster_name
  location = var.region          # regional => nodes spread across ALL zones

  network    = google_compute_network.mesh.id
  subnetwork = google_compute_subnetwork.mesh.id
  ...
}

variable "zones" {
  default = ["us-central1-a", "us-central1-b"]   # -b: GCE_STOCKOUT
}
```

After - node zones pinned on the cluster itself (this also constrains the
temporary default pool created before `remove_default_node_pool` kicks in):

```hcl
resource "google_container_cluster" "mesh" {
  name     = var.cluster_name
  location = var.region

  # Pin node zones explicitly: without this a regional cluster spreads nodes
  # across all zones in the region, including ones with GCE_STOCKOUT.
  node_locations = var.zones

  network    = google_compute_network.mesh.id
  subnetwork = google_compute_subnetwork.mesh.id
  ...
}

variable "zones" {
  default = ["us-central1-a"]    # only zone with e2 capacity that day
}
```

## 2. Docker build died under emulation

**Symptom:** `docker build --platform linux/amd64` (on an Apple Silicon Mac)
failed with exit code 2 during `go install` of the protoc plugins.

**Cause:** the whole build stage ran under QEMU emulation; the Go toolchain is
unreliable under it.

**Fix:** cross-compile instead of emulate - build stage pinned to
`--platform=$BUILDPLATFORM` (native arm64), with `GOOS/GOARCH` from
`TARGETOS/TARGETARCH` applied only to the final `go build`. Emulation
eliminated, build time cut ~10×.

**Code change** (`grpc-hello-app/Dockerfile`):

Before - with `docker build --platform linux/amd64`, the *entire* build stage
(protoc, `go install`, `go build`) runs in an emulated amd64 container:

```dockerfile
FROM golang:1.23-alpine AS build
...
RUN go mod tidy && \
    CGO_ENABLED=0 go build -trimpath -o /out/server ./cmd/server && \
    CGO_ENABLED=0 go build -trimpath -o /out/client ./cmd/client
```

After - the build stage always runs on the host's native architecture; only
the compiled *output* targets amd64 (trivial for pure Go):

```dockerfile
FROM --platform=$BUILDPLATFORM golang:1.23-alpine AS build
ARG TARGETOS
ARG TARGETARCH
...
RUN go mod tidy && \
    CGO_ENABLED=0 GOOS=${TARGETOS:-linux} GOARCH=${TARGETARCH} go build -trimpath -o /out/server ./cmd/server && \
    CGO_ENABLED=0 GOOS=${TARGETOS:-linux} GOARCH=${TARGETARCH} go build -trimpath -o /out/client ./cmd/client
```

(The related first-order mistake: the very first image was built without
`--platform` at all - an arm64 image that GKE's amd64 nodes would have
rejected with `exec format error`. The Makefile now always passes
`--platform linux/amd64`.)

## 3. Argo CD `ComparisonError: authentication required`

**Symptom:** Application stuck `sync=Unknown`, repo-server couldn't fetch.

**Diagnosis:** tested Git access *from inside the cluster*, which is the view
that matters:

```bash
kubectl exec -n argocd deploy/argocd-repo-server -- \
  git ls-remote https://github.com/noyblum/grpc-proxyless-assignment.git HEAD
```

The repo was private; Argo CD had no credential.

**Fix:** made the repo public (it's an assignment; no secrets are committed -
state files and tfvars are gitignored). The private-repo alternative is a
repository secret labeled `argocd.argoproj.io/secret-type=repository` with a
read-only PAT.

## 4. Server pods healthy but endpoints UNHEALTHY + client `DeadlineExceeded`

**Symptom:** all pods `Running`, NEG attached, but:

```bash
gcloud compute backend-services get-health helloworld-grpc-service --global
# healthState: UNHEALTHY (×3)
kubectl logs -n proxyless deploy/helloworld-client
# SayHello failed: ... waiting for new LB policy update: context deadline exceeded
```

**Diagnosis:** the server logs held the answer:

```
ERROR: [xds] Listener "[::]:50051" entering mode: "NOT_SERVING" due to error:
resource name "grpc/server?xds.resource.listening_address=[::]:50051"
of type Listener not found in received response
```

The server was built with `xds.NewGRPCServer`, which refuses connections until
the control plane sends it a server-side Listener resource. Cloud Service Mesh
only distributes those when **server-side security policies** are configured -
in a plain proxyless LB setup they never arrive, so the server rejected
everything, including its own health checks; with zero healthy endpoints the
control plane had no endpoints to push to the client.

**Fix:** serve with a plain `grpc.Server` (+ the gRPC health service). In
proxyless CSM, xDS discovery/load-balancing is a *client-side* mechanism; the
server's mesh participation is via NEG endpoints and health checks.

**Code change** (`grpc-hello-app/cmd/server/server.go`, shipped as image
`v0.1.1`; the client is unchanged - it keeps `xds:///` + the xDS credentials):

Before - an xDS-enabled server that waits for a server-side Listener resource
Cloud Service Mesh will never send (no security policies configured):

```go
import (
    "google.golang.org/grpc"
    "google.golang.org/grpc/credentials/insecure"
    xdscreds "google.golang.org/grpc/credentials/xds"
    "google.golang.org/grpc/xds"
)

creds, err := xdscreds.NewServerCredentials(xdscreds.ServerOptions{
    FallbackCreds: insecure.NewCredentials(),
})
server, err := xds.NewGRPCServer(grpc.Creds(creds))   // NOT_SERVING forever
```

After - a plain gRPC server; the health service is what the mesh actually
probes:

```go
import (
    "google.golang.org/grpc"
    "google.golang.org/grpc/health"
    healthpb "google.golang.org/grpc/health/grpc_health_v1"
)

server := grpc.NewServer()
pb.RegisterGreeterServer(server, &greeter{hostname: hostname})

healthServer := health.NewServer()
healthServer.SetServingStatus("", healthpb.HealthCheckResponse_SERVING)
healthpb.RegisterHealthServer(server, healthServer)
```

Issues 1 and 3 required no application-code change (infrastructure
configuration and repository visibility respectively).
