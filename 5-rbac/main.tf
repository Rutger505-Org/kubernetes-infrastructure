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

# Service account that backs the long-lived, log-only debug kubeconfig.
resource "kubernetes_service_account" "readonly" {
  metadata {
    name      = "readonly"
    namespace = kubernetes_namespace.readonly.metadata[0].name
  }
}

# Long-lived (non-expiring) token for the read-only service account. Since
# Kubernetes 1.24 a service account no longer gets a token secret created
# automatically, so we request one explicitly. `wait_for_service_account_token`
# makes Tofu block until the token controller has populated `.data.token`,
# so the kubeconfig output below is always complete after an apply.
#
# Trade-off vs. `kubectl create token`: this token does not expire on its own.
# It is the "permanent kubeconfig" we want, but to revoke it you must delete
# this secret (and re-apply to mint a fresh one).
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
