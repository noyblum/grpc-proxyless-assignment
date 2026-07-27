resource "google_compute_network" "mesh" {
  name                    = "grpc-mesh-vpc"
  auto_create_subnetworks = false

  depends_on = [google_project_service.required]
}

resource "google_compute_subnetwork" "mesh" {
  name          = "grpc-mesh-subnet"
  region        = var.region
  network       = google_compute_network.mesh.id
  ip_cidr_range = "10.10.0.0/20"

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.20.0.0/16"
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.30.0.0/20"
  }
}

# Google health-check probes reach NEG endpoints directly on the serving port.
resource "google_compute_firewall" "allow_health_checks" {
  name    = "grpc-mesh-allow-health-checks"
  network = google_compute_network.mesh.id

  direction     = "INGRESS"
  source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]
  target_tags   = ["allow-health-checks"]

  allow {
    protocol = "tcp"
    ports    = [tostring(var.grpc_port)]
  }
}

# Pod-to-pod gRPC traffic: proxyless clients dial server pod IPs directly.
resource "google_compute_firewall" "allow_internal_grpc" {
  name    = "grpc-mesh-allow-internal"
  network = google_compute_network.mesh.id

  direction     = "INGRESS"
  source_ranges = ["10.10.0.0/20", "10.20.0.0/16"]

  allow {
    protocol = "tcp"
  }
  allow {
    protocol = "udp"
  }
  allow {
    protocol = "icmp"
  }
}
