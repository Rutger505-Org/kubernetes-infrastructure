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
    resources  = ["deployments", "replicasets", "statefulsets"]
    verbs      = ["get", "list", "watch"]
  }

  # Services and namespaces are needed to inspect LoadBalancer IPs and
  # mc-router's routing annotations while validating deployments.
  rule {
    api_groups = [""]
    resources  = ["services", "namespaces", "persistentvolumeclaims"]
    verbs      = ["get", "list", "watch"]
  }
}

# Bound to a user name instead of a service account: the user is the CN of a
# client certificate signed by the k3s client CA. That CA survives a cluster
# rebuild (K3S_CA_BUNDLE in homelab-infrastructure) and a user name has no
# UID, so the kubeconfig keeps working after a reinstall. See the README.
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
    api_group = "rbac.authorization.k8s.io"
    kind      = "User"
    name      = "readonly"
  }
}
