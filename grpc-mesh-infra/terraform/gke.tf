resource "google_container_cluster" "mesh" {
  name     = var.cluster_name
  location = var.region

  network    = google_compute_network.mesh.id
  subnetwork = google_compute_subnetwork.mesh.id

  # VPC-native (alias IP) is required for NEGs: pod IPs are first-class VPC
  # addresses that Cloud Service Mesh hands straight to proxyless clients.
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # Workload Identity lets the app's KSA impersonate a GSA that holds
  # roles/trafficdirector.client for the xDS control-plane connection.
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  release_channel {
    channel = "REGULAR"
  }

  remove_default_node_pool = true
  initial_node_count       = 1
  deletion_protection      = false

  depends_on = [google_project_service.required]
}

resource "google_container_node_pool" "default" {
  name           = "default-pool"
  cluster        = google_container_cluster.mesh.id
  node_locations = var.zones
  node_count     = 1 # per zone

  node_config {
    machine_type    = "e2-standard-2"
    service_account = google_service_account.gke_nodes.email

    # cloud-platform scope + IAM-based restriction is the current best
    # practice, and is required for the TD/xDS API connection from nodes.
    oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]

    tags = ["allow-health-checks"]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }
}
