# Argo CD, installed by Terraform; everything under k8s/ is then delivered by
# Argo CD from this repo (see ../argocd/root-app.yaml).
resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true

  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version

  # Keep the API server private; access it with kubectl port-forward.
  set {
    name  = "configs.params.server\\.insecure"
    value = "true"
  }

  depends_on = [google_container_node_pool.default]
}
