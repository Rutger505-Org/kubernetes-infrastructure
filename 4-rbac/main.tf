terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
  }

  backend "kubernetes" {
    config_path   = "~/.kube/config"
    secret_suffix = "rbac"
  }
}

provider "kubernetes" {
  config_path = "~/.kube/config"
}

resource "kubernetes_namespace" "readonly" {
  metadata {
    name = "read-only-access"
  }
}

resource "kubernetes_service_account" "readonly" {
  metadata {
    name      = "readonly"
    namespace = kubernetes_namespace.readonly.metadata[0].name
  }
}

resource "kubernetes_secret" "readonly_token" {
  metadata {
    name      = "readonly-token"
    namespace = kubernetes_namespace.readonly.metadata[0].name
    annotations = {
      "kubernetes.io/service-account.name" = kubernetes_service_account.readonly.metadata[0].name
    }
  }

  type                           = "kubernetes.io/service-account-token"
  wait_for_service_account_token = true
}

resource "kubernetes_cluster_role" "log_reader" {
  metadata {
    name = "log-reader"
  }

  rule {
    api_groups = [""]
    resources  = ["pods", "pods/log", "events"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "replicasets"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_cluster_role_binding" "readonly" {
  metadata {
    name = "readonly-log-reader"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.log_reader.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.readonly.metadata[0].name
    namespace = kubernetes_service_account.readonly.metadata[0].namespace
  }
}
