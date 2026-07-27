# --- GKE node service account -------------------------------------------------
resource "google_service_account" "gke_nodes" {
  account_id   = "gke-grpc-mesh-nodes"
  display_name = "GKE nodes for grpc-mesh-cluster"
}

resource "google_project_iam_member" "gke_nodes" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
    "roles/artifactregistry.reader",
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

# --- Workload identity for the proxyless gRPC app -----------------------------
# The server and client pods run as KSA proxyless/grpc-app-sa, which
# impersonates this GSA. roles/trafficdirector.client authorizes the xDS
# (ADS) stream to trafficdirector.googleapis.com.
resource "google_service_account" "grpc_app" {
  account_id   = "grpc-mesh-app"
  display_name = "Proxyless gRPC demo workloads"
}

resource "google_project_iam_member" "grpc_app_td_client" {
  project = var.project_id
  role    = "roles/trafficdirector.client"
  member  = "serviceAccount:${google_service_account.grpc_app.email}"
}

resource "google_service_account_iam_member" "grpc_app_wi" {
  service_account_id = google_service_account.grpc_app.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[proxyless/grpc-app-sa]"
}
