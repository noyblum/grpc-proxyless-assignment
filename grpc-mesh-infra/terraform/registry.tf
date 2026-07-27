resource "google_artifact_registry_repository" "grpc_demo" {
  repository_id = "grpc-demo"
  location      = var.region
  format        = "DOCKER"
  description   = "Images for the proxyless gRPC demo"

  depends_on = [google_project_service.required]
}
