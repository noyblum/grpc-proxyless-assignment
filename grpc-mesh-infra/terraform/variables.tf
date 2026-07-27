variable "project_id" {
  description = "GCP project ID to deploy into."
  type        = string
}

variable "region" {
  description = "Region for the GKE cluster, subnet and Artifact Registry."
  type        = string
  default     = "us-central1"
}

variable "zones" {
  description = "Zones for GKE nodes; also the zones where the server NEGs are created."
  type        = list(string)
  default     = ["us-central1-a", "us-central1-b"]
}

variable "cluster_name" {
  description = "GKE cluster name."
  type        = string
  default     = "grpc-mesh-cluster"
}

variable "mesh_name" {
  description = "Cloud Service Mesh Mesh resource name (referenced by td-grpc-bootstrap --config-mesh)."
  type        = string
  default     = "grpc-mesh"
}

variable "route_hostname" {
  description = "GRPCRoute hostname; clients dial xds:///<route_hostname>."
  type        = string
  default     = "helloworld-gke"
}

variable "grpc_port" {
  description = "Serving port of the Greeter server."
  type        = number
  default     = 50051
}

variable "neg_name" {
  description = "Name of the standalone NEG declared in the Kubernetes Service annotation."
  type        = string
  default     = "helloworld-grpc-neg"
}

variable "attach_neg_backends" {
  description = <<-EOT
    Whether to attach the GKE-created NEGs to the backend service. Keep false on
    the first apply (the NEGs only exist after Argo CD deploys the Kubernetes
    Service with its NEG annotation), then re-apply with true.
  EOT
  type        = bool
  default     = false
}

variable "argocd_chart_version" {
  description = "argo-cd Helm chart version."
  type        = string
  default     = "7.7.11"
}
