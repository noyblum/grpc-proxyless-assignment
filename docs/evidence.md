# Deployment evidence

## Argo CD — application synced and healthy

The `proxyless-demo` Application, synced from
`github.com/noyblum/grpc-proxyless-assignment` (`grpc-mesh-infra/k8s/proxyless-demo`),
deployed in-cluster to the `proxyless` namespace:

![Argo CD applications list](screenshots/argocd-applications.png)

Resource tree — Deployments → ReplicaSets → 3 server pods + 1 client pod, the
NEG Service (`servicenetworkendpointgroup helloworld-grpc-neg`) and the
Workload Identity service account, all Healthy:

![Argo CD application tree](screenshots/argocd-app-tree.png)

## Per-RPC load balancing (client logs)

Replies rotate across all three server pod hostnames — request-level balancing
over a single client channel, which DNS + kube-proxy can never do. Captured
from the live deployment:

```
$ kubectl logs -n proxyless deploy/helloworld-client -f
2026/07/27 19:28:50 reply: Hello helloworld-client-86dfcb7d58-9h5rf, from helloworld-server-6f6ddf4db9-5xsf7
2026/07/27 19:28:52 reply: Hello helloworld-client-86dfcb7d58-9h5rf, from helloworld-server-6f6ddf4db9-rdqqj
2026/07/27 19:28:54 reply: Hello helloworld-client-86dfcb7d58-9h5rf, from helloworld-server-6f6ddf4db9-nm2ch
2026/07/27 19:28:56 reply: Hello helloworld-client-86dfcb7d58-9h5rf, from helloworld-server-6f6ddf4db9-5xsf7
2026/07/27 19:28:58 reply: Hello helloworld-client-86dfcb7d58-9h5rf, from helloworld-server-6f6ddf4db9-rdqqj
2026/07/27 19:29:00 reply: Hello helloworld-client-86dfcb7d58-9h5rf, from helloworld-server-6f6ddf4db9-nm2ch
```

The channel target is `xds:///helloworld-gke` — a single gRPC channel; the
strict 3-pod round-robin is the mesh's endpoint-level policy at work.

## Backend health

All three NEG endpoints (the server pods) pass the mesh's gRPC health check:

```
$ gcloud compute backend-services get-health helloworld-grpc-service --global
healthState: HEALTHY   (×3 NEG endpoints, port 50051)
```
