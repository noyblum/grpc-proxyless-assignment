# Architecture

![Architecture diagram](../assets/architecture.svg)

## Components

| Component | Role |
|---|---|
| **Terraform** ([grpc-mesh-infra/terraform](../grpc-mesh-infra/terraform)) | Provisions the entire GCP environment: APIs, VPC + firewall, GKE (Workload Identity, VPC-native), IAM, Artifact Registry, the Cloud Service Mesh resources, and Argo CD (Helm). |
| **Argo CD** (in-cluster, `argocd` namespace) | Owns everything application-shaped. Pulls this Git repo and applies `grpc-mesh-infra/k8s/proxyless-demo` into the `proxyless` namespace with automated sync, prune and self-heal. |
| **Mesh + GRPCRoute** | `Mesh grpc-mesh` is the configuration scope; `GRPCRoute helloworld-grpc-route` maps hostname `helloworld-gke` to the backend service. |
| **Backend service** | `helloworld-grpc-service` - protocol `GRPC`, scheme `INTERNAL_SELF_MANAGED` (mandatory for CSM), gRPC health check, backed by the GKE-created NEG. |
| **NEG** `helloworld-grpc-neg` | Created by GKE from the Service annotation `cloud.google.com/neg`; holds the server pod `IP:50051` endpoints. |
| **Server pods** (×3) | Plain gRPC Greeter + gRPC health protocol on :50051. Replies embed the pod hostname to make load balancing observable. |
| **Client pod** | Dials `xds:///helloworld-gke`. The grpc-go xDS resolver streams config from `trafficdirector.googleapis.com` and balances every RPC across the three pod IPs directly - no proxy, no DNS, no kube-proxy. |
| **td-grpc-bootstrap init container** | Generates the bootstrap file (`GRPC_XDS_BOOTSTRAP`) pointing the gRPC library at the control plane with `--config-mesh=grpc-mesh`. |

## Where xDS lives (and where it doesn't)

A subtle point discovered during deployment: in a plain proxyless load-balancing
setup, **xDS is client-side only**. Servers participate in the mesh through the
NEG + health-check path; the control plane only distributes *server-side*
Listener resources when server-side security policies (mTLS) are configured.
An `xds.NewGRPCServer` without such policies waits forever for its Listener
resource and stays `NOT_SERVING` - see
[troubleshooting.md](troubleshooting.md#4-server-pods-healthy-but-endpoints-unhealthy--client-deadlineexceeded).
