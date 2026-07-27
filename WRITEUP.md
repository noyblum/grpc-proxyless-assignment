# Technical Write-up — gRPC Load Balancing & Proxyless Service Mesh on GCP

Senior DevOps Engineer home assignment — Part 1 (analysis) and architecture justification for Part 2.

---

## Task 1 — Why gRPC over HTTP/2 with DNS resolution breaks load balancing

### The mechanics

gRPC runs on **HTTP/2**, which was explicitly designed to open **a single long-lived TCP
connection per target** and **multiplex** all concurrent requests (streams) over it. A gRPC
channel therefore resolves its target **once**, at connection-establishment time, picks the
address(es) DNS returned, and then keeps reusing the same connection(s) for hours or days.

Kubernetes breaks this in two compounding ways:

1. **ClusterIP Services hide the endpoints.** DNS for a normal Service returns exactly one
   virtual IP. The gRPC client sees *one* address, opens *one* connection, and every RPC it
   ever sends is multiplexed onto it. `kube-proxy` (iptables/IPVS) balances at **L4 —
   per-connection, not per-request** — so it picks one backend pod when the TCP connection is
   created and then never again. All traffic from that client is pinned to one pod.

2. **DNS is not re-resolved on cluster changes.** The gRPC DNS resolver has no TTL-driven
   refresh loop; re-resolution is only triggered by connection breakage. Even with a headless
   Service (which returns all pod IPs), scale-ups and pod replacements are invisible to a
   client holding healthy connections.

### Concrete issues (at least two)

| # | Issue | Effect in Kubernetes |
|---|-------|----------------------|
| 1 | **Traffic pinning / hot pod** | With N server pods, a client sends 100% of its RPCs to 1 pod. One replica saturates CPU while its siblings idle. HPA sees *average* utilization and may not even scale. |
| 2 | **Scaling out does nothing** | New pods added by the HPA (or by you, in a panic) receive **zero traffic** — existing clients never learn about them because nothing re-resolves DNS. You pay for capacity that carries no load. |
| 3 | **Rolling updates cause traffic avalanches** | When pinned pods terminate, all their clients reconnect *simultaneously* — and again each pins to a single (possibly the same first-Ready) pod, causing serial hot-spotting and error spikes during deploys. |
| 4 | **Stale endpoints / slow failover** | A client keeps sending RPCs into a connection to a pod that is `Terminating` or unhealthy until TCP actually fails (which with keepalives off can take minutes), producing `UNAVAILABLE` bursts. |

Real-world illustration: Jamf's engineering team hit exactly this — pods at wildly uneven CPU,
HPA scaling that didn't relieve the hot replica — and their initial fix was the server-side
`MaxConnectionAge` keepalive trick to force periodic reconnects (see links below). That
*mitigates* but does not solve: it converts "permanently pinned" into "re-pinned every N
minutes," still connection-level rather than request-level balancing.

### Why HTTP/1.1 doesn't suffer from this

HTTP/1.1 has **no multiplexing**: one in-flight request per connection. Clients therefore hold
a *pool* of relatively short-lived connections and open new ones whenever concurrency rises or
keep-alive idle timeouts close them. Because connections are created constantly, **L4
(per-connection) balancing approximates per-request balancing** — every new connection is a
fresh kube-proxy/L4 balancing decision, so traffic naturally spreads across pods and new pods
start receiving connections almost immediately. With HTTP/2, connection creation is a
once-per-process event, so a per-connection balancer only ever makes one decision.

---

## Task 2 — Solutions comparison and recommendation

### Option A: Golang client-side changes (no mesh)

Use a **headless Service** + the `dns:///` resolver + `round_robin` LB policy, plus
server-side `keepalive.ServerParameters{MaxConnectionAge: ...}` to force periodic
re-resolution:

```go
conn, _ := grpc.NewClient(
    "dns:///helloworld.ns.svc.cluster.local:50051",
    grpc.WithDefaultServiceConfig(`{"loadBalancingConfig": [{"round_robin":{}}]}`),
)
```

* **Pros:** zero infrastructure, lowest latency (direct pod-to-pod), fully in your control.
* **Cons:** per-language and per-service effort (every client team must do it correctly);
  DNS re-resolution is still event-driven, so scale-up reaction depends on
  `MaxConnectionAge` churn; no uniform policy layer (retries, mTLS, traffic splitting,
  observability) — each of those becomes more bespoke code. Fine for 3 services, painful for 50.

### Option B: Linkerd (sidecar mesh)

Linkerd ships an ultra-light Rust micro-proxy per pod that watches the Kubernetes API and does
**request-level** (HTTP/2-stream-aware) balancing with an EWMA latency-aware algorithm —
gRPC load balancing works with literally **zero configuration and zero code changes**.
Buoyant's 2026 benchmark shows it with the tightest tail latencies among Linkerd/Istio/Cilium
for gRPC balancing.

* **Pros:** best day-1 DX of any mesh, tiny resource footprint, automatic mTLS, language-agnostic.
* **Cons:** it is still a **sidecar per pod** — added hop, added container to schedule and
  upgrade (proxy version churn on every rollout), and you now operate a mesh control plane
  yourself. Not GCP-managed.

### Option C: Envoy (standalone or Istio-based)

Envoy is the industry-standard L7 proxy: full request-level gRPC balancing, rich policy
(retries, outlier detection, traffic splitting), and the origin of the **xDS** APIs. You can run
it as a sidecar (Istio), as a per-node/ambient deployment, or as a middle proxy.

* **Pros:** most feature-complete traffic management on the market; xDS ecosystem standard.
* **Cons:** highest operational complexity when self-managed — you own the control plane
  (Istio/Contour/self-built), its upgrades, and its failure modes. Sidecar resource cost at
  scale is real (though Istio ambient mode now reduces it).

### Option D: Managed service mesh solutions

* **GCP — Cloud Service Mesh** (successor to Traffic Director + Anthos Service Mesh):
  Google-managed control plane speaking **open-source xDS**. Two data-plane models: managed
  Envoy sidecars, or **proxyless gRPC**, where the gRPC library itself is the xDS client.
* **AWS App Mesh:** reached end-of-support (September 2026) — AWS is steering users to VPC
  Lattice / ECS Service Connect; not a safe bet.
* **Istio-as-a-service** (e.g., GKE's managed CSM in-cluster control plane, or third-party
  offerings like Solo/Tetrate): managed lifecycle for Istio, still sidecar-centric by default.

### Best fit for a GCP environment — and why

**Recommendation: Google Cloud Service Mesh with proxyless gRPC (xDS) for the Golang gRPC
east-west traffic**, with managed Envoy sidecars only where non-gRPC or polyglot workloads need
mesh features.

Justification against the alternatives:

1. **Solves the actual problem at the right layer.** grpc-go (≥1.68 for current CSM features)
   natively implements the xDS APIs ([gRFC A27](https://github.com/grpc/proposal/blob/master/A27-xds-global-load-balancing.md)
   and successors): the *client library itself* receives endpoint lists (EDS), balancing policy,
   and health status from the control plane and balances **per-RPC** across pod IPs. DNS is
   removed from the picture entirely.
2. **No sidecars ⇒ no proxy tax.** No extra container per pod, no added network hop (Google
   measured the removed hop as the main latency win of proxyless), no proxy fleet to upgrade —
   which is precisely the ops burden that makes Linkerd/Istio costly at fleet scale.
3. **Managed control plane.** Google runs the xDS control plane (`trafficdirector.googleapis.com`)
   with an SLA; we operate zero mesh infrastructure. Compare: self-managed Istio/Linkerd
   control-plane upgrades are recurring toil and outage risk.
4. **GCP-native integration.** Backend services, gRPC health checks, standalone NEGs, Cloud
   Monitoring, and IAM (`roles/trafficdirector.client`) are first-class; the same mesh model
   extends to Cloud Run and GCE VMs, not just GKE.
5. **Trade-offs acknowledged (why not the others):** client-side-only Go changes don't give a
   policy/observability layer and don't scale organizationally; Linkerd is superb DX but is
   self-operated and sidecar-based; self-managed Envoy/Istio is maximum power but maximum toil;
   AWS App Mesh is being sunset and is irrelevant on GCP. Proxyless CSM's own limitations are
   fair to note: gRPC-only (per supported language versions), a subset of Envoy's feature set
   (see "Proxyless gRPC limitations" link), and xDS coupling inside the app process. For a
   Golang-centric gRPC platform on GCP those limits are acceptable — and sidecar Envoy under
   the *same* mesh covers the exceptions.

### Avoiding sidecar proxies — Golang-centric mechanics

How a Go service participates in the mesh with no proxy at all:

1. Import the xDS packages: `_ "google.golang.org/grpc/xds"` (client) /
   `google.golang.org/grpc/xds.NewGRPCServer` (server).
2. Provide a **bootstrap file** (`GRPC_XDS_BOOTSTRAP` env var) telling the library where the
   xDS server is and which mesh it belongs to. On GKE, the
   `gcr.io/trafficdirector-prod/td-grpc-bootstrap` init container generates it
   (`--config-mesh=<mesh>`); a namespace label (`mesh.cloud.google.com/csm-injection=proxyless`)
   can auto-inject it.
3. Clients dial `xds:///<GRPCRoute-hostname>` instead of a DNS name. The library opens an ADS
   stream to Cloud Service Mesh, receives listener → route → cluster → endpoints (LDS/RDS/CDS/EDS),
   and load-balances every RPC across the NEG endpoints, reacting to scale events and health
   checks in near-real-time — exactly what DNS could never do.

### References

* [gRPC Load Balancing on Kubernetes without Tears — Kubernetes blog](https://kubernetes.io/blog/2018/11/07/grpc-load-balancing-on-kubernetes-without-tears/)
* [Load balancing and scaling long-lived connections in Kubernetes — LearnKube](https://learnkube.com/kubernetes-long-lived-connections)
* [How three lines of configuration solved our gRPC scaling issues in Kubernetes — Jamf Engineering](https://medium.com/jamf-engineering/how-three-lines-of-configuration-solved-our-grpc-scaling-issues-in-kubernetes-ca1ff13f7f06)
* [gRPC Load Balancing (official gRPC blog)](https://grpc.io/blog/grpc-load-balancing/)
* [gRPC load balancing with grpc-go — Rafael Eyng](https://rafaeleyng.github.io/grpc-load-balancing-with-grpc-go)
* [Cloud Service Mesh with proxyless gRPC services — overview](https://docs.cloud.google.com/service-mesh/docs/service-routing/proxyless-overview)
* [Set up proxyless gRPC services (Mesh + GRPCRoute)](https://docs.cloud.google.com/service-mesh/docs/service-routing/set-up-proxyless-mesh)
* [Set up a proxyless gRPC service mesh on GKE](https://docs.cloud.google.com/service-mesh/docs/gateway/proxyless-grpc-mesh)
* [Proxyless gRPC limitations](https://docs.cloud.google.com/service-mesh/docs/service-routing/limitations-proxyless)
* [gRFC A27 — xDS-based global load balancing](https://github.com/grpc/proposal/blob/master/A27-xds-global-load-balancing.md)
* [Benchmarking gRPC load balancing: Linkerd vs Istio vs Cilium — Buoyant (2026)](https://www.buoyant.io/blog/benchmarking-grpc-load-balancing-on-kubernetes-linkerd-vs-istio-vs-cilium)
* [gRPC Load Balancing on Kubernetes without Tears — Linkerd](https://linkerd.io/2018/11/14/grpc-load-balancing-on-kubernetes-without-tears/)
* [grpc-go xDS examples](https://github.com/grpc/grpc-go/tree/master/examples/features/xds)
