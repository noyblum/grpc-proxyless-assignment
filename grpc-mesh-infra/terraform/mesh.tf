# --- Cloud Service Mesh (proxyless gRPC) --------------------------------------
# Mesh: the configuration scope that td-grpc-bootstrap points workloads at
# via --config-mesh.
resource "google_network_services_mesh" "grpc" {
  name = var.mesh_name

  depends_on = [google_project_service.required]
}

# gRPC health check against the standard gRPC health-checking protocol served
# by the application on its serving port.
resource "google_compute_health_check" "grpc" {
  name = "helloworld-grpc-hc"

  grpc_health_check {
    port = var.grpc_port
  }

  depends_on = [google_project_service.required]
}

# The standalone NEGs are created by GKE from the Kubernetes Service
# annotation cloud.google.com/neg '{"exposed_ports":{"50051":{"name":"helloworld-grpc-neg"}}}'
# — one per zone that hosts server pods. They only exist after Argo CD has
# synced the app, hence the attach_neg_backends two-phase flag.
data "google_compute_network_endpoint_group" "server" {
  for_each = var.attach_neg_backends ? toset(var.zones) : toset([])

  name = var.neg_name
  zone = each.value
}

# Backend service: in every Cloud Service Mesh deployment the load-balancing
# scheme must be INTERNAL_SELF_MANAGED and the protocol GRPC.
resource "google_compute_backend_service" "grpc" {
  name                  = "helloworld-grpc-service"
  load_balancing_scheme = "INTERNAL_SELF_MANAGED"
  protocol              = "GRPC"
  health_checks         = [google_compute_health_check.grpc.id]

  dynamic "backend" {
    for_each = data.google_compute_network_endpoint_group.server

    content {
      group                 = backend.value.id
      balancing_mode        = "RATE"
      max_rate_per_endpoint = 100
    }
  }
}

# GRPCRoute: maps the xds:/// hostname clients dial to the backend service.
# Both hostname forms are listed so channel targets with and without an
# explicit port match.
resource "google_network_services_grpc_route" "hello" {
  name      = "helloworld-grpc-route"
  hostnames = [var.route_hostname, "${var.route_hostname}:${var.grpc_port}"]
  meshes    = [google_network_services_mesh.grpc.id]

  rules {
    action {
      destinations {
        service_name = google_compute_backend_service.grpc.id
      }
    }
  }
}
