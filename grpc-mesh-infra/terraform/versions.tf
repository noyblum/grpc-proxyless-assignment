terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.16"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

data "google_project" "this" {}

data "google_client_config" "this" {}

# Helm provider authenticates against the GKE cluster created below, used to
# install Argo CD.
provider "helm" {
  kubernetes {
    host                   = "https://${google_container_cluster.mesh.endpoint}"
    token                  = data.google_client_config.this.access_token
    cluster_ca_certificate = base64decode(google_container_cluster.mesh.master_auth[0].cluster_ca_certificate)
  }
}
