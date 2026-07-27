# grpc-mesh-infra - GitOps / IaC Repository

Terraform for the GCP environment (GKE + Cloud Service Mesh proxyless gRPC +
Argo CD) and the Kubernetes manifests that Argo CD delivers.

## Layout

```
terraform/            # GCP: APIs, VPC, GKE, IAM/WI, Artifact Registry,
                      # Mesh + GRPCRoute + backend service + health check, Argo CD
k8s/proxyless-demo/   # Namespace, KSA, server/client Deployments, NEG Service
argocd/root-app.yaml  # Argo CD Application syncing k8s/proxyless-demo
```

## Architecture

```
client pod ──xds:///helloworld-gke──▶ trafficdirector.googleapis.com (ADS)
   │                                        ▲            │ LDS/RDS/CDS/EDS
   │ per-RPC LB, direct to pod IPs          │            ▼
   └───────▶ server pods :50051 ◀── NEG ── backend service ◀── GRPCRoute ◀── Mesh
                    ▲
             gRPC health checks (35.191.0.0/16, 130.211.0.0/22)
```

No sidecars anywhere: the grpc-go library in each pod is the xDS client.

## Deployment runbook

Prereqs: `gcloud` authenticated with owner/editor on the target project,
`terraform` >= 1.5, `kubectl`, `docker`.

```bash
cd terraform

# 1. Base infrastructure (NEGs don't exist yet, so backends stay detached)
terraform init
terraform apply -var project_id=<PROJECT_ID>

# 2. Build & push the app image (from the application repo:
#    https://github.com/noyblum/grpc-hello-app)
git clone https://github.com/noyblum/grpc-hello-app.git /tmp/grpc-hello-app
make -C /tmp/grpc-hello-app docker-push PROJECT_ID=<PROJECT_ID>

# 3. Point kubectl at the cluster
$(terraform output -raw get_credentials)

# 4. Replace placeholders in the manifests, commit & push this repo:
#    - PROJECT_ID in k8s/proxyless-demo/serviceaccount.yaml and both Deployments
#    - repoURL in argocd/root-app.yaml
# then hand the app to Argo CD (the only manual kubectl apply - Application
# CRDs can't be terraform-planned before Argo CD's CRDs exist):
kubectl apply -f ../argocd/root-app.yaml

# 5. Once the server pods are Ready, GKE has created the named NEGs
#    (helloworld-grpc-neg) in each zone - attach them to the backend service:
terraform apply -var project_id=<PROJECT_ID> -var attach_neg_backends=true
```

### Argo CD UI

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
kubectl -n argocd port-forward svc/argocd-server 8080:80
# open http://localhost:8080  (user: admin)
```

## Verification (screenshot checklist)

1. **Argo CD UI** - `proxyless-demo` application `Synced` / `Healthy`.
2. **Client logs prove per-RPC load balancing** - replies alternate between the
   three server pod hostnames:
   ```bash
   kubectl -n proxyless logs deploy/helloworld-client -f
   # reply: Hello helloworld-client-..., from helloworld-server-abc
   # reply: Hello helloworld-client-..., from helloworld-server-def
   # reply: Hello helloworld-client-..., from helloworld-server-ghi
   ```
3. **Backend health** - Console → Network Services → Traffic Director /
   Cloud Service Mesh: mesh `grpc-mesh`, route `helloworld-grpc-route`, and
   ```bash
   gcloud compute backend-services get-health helloworld-grpc-service --global
   ```
   showing all NEG endpoints `HEALTHY`.
4. **Scaling reacts instantly** (the point of the whole exercise):
   ```bash
   kubectl -n proxyless scale deploy/helloworld-server --replicas=5
   ```
   New pod hostnames appear in the client logs within seconds - no
   reconnects, no DNS, no sidecars.

## Notes & decisions

* `attach_neg_backends` exists because the NEGs are created *by GKE* when Argo
  CD syncs the Service; Terraform can only data-source them afterwards. In a
  production setup I'd break the mesh layer into its own root module (or use
  the `gke-autoneg-controller`) to remove the two-phase apply.
* The backend service uses `INTERNAL_SELF_MANAGED` + `GRPC` - mandatory for
  Cloud Service Mesh.
* Argo CD is installed by Terraform (helm_release) as bootstrap; everything
  application-shaped is Git-driven from `k8s/` with automated sync, prune and
  self-heal.
