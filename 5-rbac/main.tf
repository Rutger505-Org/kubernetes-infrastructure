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

# Dedicated namespace that holds read-only debug service accounts. No
# workloads or secrets live here; it only exists to anchor the accounts.
resource "kubernetes_namespace" "readonly" {
  metadata {
    name = "readonly"
  }
}

# Service account used to hand out short-lived, log-only access. Tokens are
# minted on demand with `kubectl create token readonly -n readonly --duration=2h`
# and are never stored in state.
resource "kubernetes_service_account" "readonly" {
  metadata {
    name      = "readonly"
    namespace = kubernetes_namespace.readonly.metadata[0].name
  }
}

# Cluster-wide read access to pods, their logs and events, plus the workload
# objects needed to debug a rollout. Deliberately excludes "secrets" and
# "configmaps" so a holder can inspect why a pod is failing without ever
# reading sensitive data. RBAC is default-deny, so only what is listed here
# is permitted.
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
