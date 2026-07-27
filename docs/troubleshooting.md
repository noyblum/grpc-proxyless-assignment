# Troubleshooting log

Real issues hit while deploying this assignment, in order, with the diagnosis
path. Kept as documentation because the debugging is at least as instructive
as the happy path.

## 1. GKE nodes never came up — `GCE_STOCKOUT`

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

## 2. Docker build died under emulation

**Symptom:** `docker build --platform linux/amd64` (on an Apple Silicon Mac)
failed with exit code 2 during `go install` of the protoc plugins.

**Cause:** the whole build stage ran under QEMU emulation; the Go toolchain is
unreliable under it.

**Fix:** cross-compile instead of emulate — build stage pinned to
`--platform=$BUILDPLATFORM` (native arm64), with `GOOS/GOARCH` from
`TARGETOS/TARGETARCH` applied only to the final `go build`. Emulation
eliminated, build time cut ~10×.

## 3. Argo CD `ComparisonError: authentication required`

**Symptom:** Application stuck `sync=Unknown`, repo-server couldn't fetch.

**Diagnosis:** tested Git access *from inside the cluster*, which is the view
that matters:

```bash
kubectl exec -n argocd deploy/argocd-repo-server -- \
  git ls-remote https://github.com/noyblum/grpc-proxyless-assignment.git HEAD
```

The repo was private; Argo CD had no credential.

**Fix:** made the repo public (it's an assignment; no secrets are committed —
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
only distributes those when **server-side security policies** are configured —
in a plain proxyless LB setup they never arrive, so the server rejected
everything, including its own health checks; with zero healthy endpoints the
control plane had no endpoints to push to the client.

**Fix:** serve with a plain `grpc.Server` (+ the gRPC health service). In
proxyless CSM, xDS discovery/load-balancing is a *client-side* mechanism; the
server's mesh participation is via NEG endpoints and health checks.
