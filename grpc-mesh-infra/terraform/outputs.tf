output "cluster_name" {
  value = google_container_cluster.mesh.name
}

output "get_credentials" {
  value = "gcloud container clusters get-credentials ${google_container_cluster.mesh.name} --region ${var.region} --project ${var.project_id}"
}

output "project_number" {
  description = "Used in the GRPCRoute/Mesh resource paths."
  value       = data.google_project.this.number
}

output "mesh_id" {
  value = google_network_services_mesh.grpc.id
}

output "backend_service" {
  value = google_compute_backend_service.grpc.id
}

output "artifact_registry" {
  value = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.grpc_demo.repository_id}"
}

output "app_service_account" {
  value = google_service_account.grpc_app.email
}
