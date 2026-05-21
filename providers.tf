terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.38.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0.2"
    }
  }

  required_version = "~> 1.15.3"
}

provider "kubernetes" {
  config_path            = "~/.kube/config"
  config_context_cluster = var.cluster_name
}

provider "helm" {
  kubernetes = {
    config_path            = "~/.kube/config"
    config_context_cluster = var.cluster_name
  }
}
