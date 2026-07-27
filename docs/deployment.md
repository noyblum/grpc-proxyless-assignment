# Deployment runbook

Prereqs: `gcloud` (authed, ADC via `gcloud auth application-default login`),
`terraform` >= 1.5, `kubectl`, `docker`. GCP project with billing enabled.

## 1. Base infrastructure

```bash
cd grpc-mesh-infra/terraform
terraform init
terraform apply -var project_id=<PROJECT_ID>
```

Creates: APIs, VPC + firewall (health-check ranges → tcp:50051), VPC-native GKE
with Workload Identity (node zones pinned via `zones` - see
[troubleshooting §1](troubleshooting.md)), IAM (`roles/trafficdirector.client`
via Workload Identity), Artifact Registry, `Mesh` + `GRPCRoute` + backend
service + gRPC health check, and Argo CD (Helm).

## 2. Build & push the app image

From the application repository
([noyblum/grpc-hello-app](https://github.com/noyblum/grpc-hello-app)):

```bash
git clone https://github.com/noyblum/grpc-hello-app.git
make -C grpc-hello-app docker-push PROJECT_ID=<PROJECT_ID> TAG=v0.1.1
```

## 3. Hand the app to Argo CD

```bash
$(terraform output -raw get_credentials)
kubectl apply -f ../argocd/root-app.yaml
```

The repo must be readable by Argo CD (public, or add a repository credential
secret). Argo CD syncs `k8s/proxyless-demo`: namespace, KSA (Workload
Identity), server Deployment ×3 + NEG Service, client Deployment.

## 4. Attach the NEGs

Once the server pods are Ready, GKE has created `helloworld-grpc-neg`:

```bash
terraform apply -var project_id=<PROJECT_ID> -var attach_neg_backends=true
```

Two-phase on purpose: the NEG is created *by GKE* when the Service syncs, so
Terraform can only data-source it afterwards.

## 5. Verify

```bash
gcloud compute backend-services get-health helloworld-grpc-service --global   # HEALTHY ×3
kubectl logs -n proxyless deploy/helloworld-client -f                          # replies rotate across server pods
```

Argo CD UI:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
kubectl port-forward -n argocd svc/argocd-server 8080:80   # http://localhost:8080, user admin
```

## Teardown

```bash
kubectl delete -f ../argocd/root-app.yaml   # let Argo prune the app resources
terraform destroy -var project_id=<PROJECT_ID>
```
