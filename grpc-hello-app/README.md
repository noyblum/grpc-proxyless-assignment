# grpc-hello-app — Application Repository

Golang gRPC Greeter service and client for a **proxyless** Cloud Service Mesh
deployment (no sidecars — the grpc-go library itself is the xDS client).

Companion GitOps/IaC repository (Terraform, Kubernetes manifests, Argo CD,
write-up and docs):
**[noyblum/grpc-proxyless-assignment](https://github.com/noyblum/grpc-proxyless-assignment)**

## Layout

```
proto/helloworld.proto     # Greeter service contract (SayHello)
cmd/server/server.go       # xDS-enabled server (xds.NewGRPCServer), port 50051
cmd/client/client.go       # client dialing xds:///helloworld-gke
Dockerfile                 # multi-stage: protoc codegen + static build + distroless
Makefile                   # proto / build / docker-build / docker-push
```

## How the xDS integration works

* Both binaries read the bootstrap file referenced by the `GRPC_XDS_BOOTSTRAP`
  environment variable. On GKE this file is generated at pod startup by the
  `gcr.io/trafficdirector-prod/td-grpc-bootstrap` init container with
  `--config-mesh=grpc-mesh` (see the GitOps repo's Kubernetes manifests).
* The **client** dials `xds:///helloworld-gke` — the hostname configured on the
  Cloud Service Mesh `GRPCRoute`. No DNS involved: endpoints, load-balancing
  policy and health status stream from `trafficdirector.googleapis.com` over ADS.
* The **server** uses `xds.NewGRPCServer` (with insecure fallback credentials)
  and serves the standard gRPC health-checking protocol on the serving port,
  which the mesh's gRPC health check probes.
* The reply message embeds the serving pod's hostname, so the client logs are
  living proof of per-RPC load balancing across replicas.

## Build & push

Generated stubs (`gen/`) are not committed; the Dockerfile runs `protoc` and
`go mod tidy` inside the builder stage, so the image builds from a clean checkout:

```bash
make docker-push PROJECT_ID=<your-project> TAG=v0.1.0
```

For local development install `protoc`, then `make build`.
