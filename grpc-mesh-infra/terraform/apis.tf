# APIs required for GKE, Cloud Service Mesh (Traffic Director xDS control
# plane) and the container image registry.
resource "google_project_service" "required" {
  for_each = toset([
    "compute.googleapis.com",
    "container.googleapis.com",
    "trafficdirector.googleapis.com",
    "networkservices.googleapis.com",
    "networksecurity.googleapis.com",
    "artifactregistry.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
  ])

  service            = each.value
  disable_on_destroy = false
}
