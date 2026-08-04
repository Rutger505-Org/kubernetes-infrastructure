terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
  }

  backend "kubernetes" {
    config_path   = "~/.kube/config"
    secret_suffix = "minio"
  }
}

provider "kubernetes" {
  config_path = "~/.kube/config"
}

provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}

# MinIO: self-hosted, S3-compatible object storage used as a personal CDN for
# sharing clips and hosting build artifacts (e.g. the soundboard APK).
#
# Storage is backed by a PersistentVolumeClaim on the node's local disk (the
# spare 250GB drives mounted into the K3s VM, exposed through the default
# local-path StorageClass). See homelab-infrastructure for the disk-mount step.
#
# Two hostnames are served through Traefik + cert-manager:
#   - cdn.rutgerpronk.com   -> the S3 API (public bucket reads = direct file URLs)
#   - minio.rutgerpronk.com -> the MinIO web console (admin only)

resource "helm_release" "minio" {
  name             = "minio"
  repository       = "https://charts.min.io/"
  chart            = "minio"
  namespace        = "minio"
  create_namespace = true
  version          = "5.4.0"

  wait    = true
  timeout = 600

  # Single-node, single-drive standalone mode (homelab scale).
  set {
    name  = "mode"
    value = "standalone"
  }

  set {
    name  = "replicas"
    value = "1"
  }

  # Root credentials come from CI vars/secrets.
  set {
    name  = "rootUser"
    value = var.root_user
  }

  set_sensitive {
    name  = "rootPassword"
    value = var.root_password
  }

  # Persistence on the node's local disk.
  set {
    name  = "persistence.enabled"
    value = "true"
  }

  set {
    name  = "persistence.size"
    value = var.storage_size
  }

  set {
    name  = "persistence.storageClass"
    value = var.storage_class
  }

  # Provision the CDN bucket up front, with public (anonymous read-only) policy
  # so uploaded files are directly linkable (and Discord can preview them).
  set {
    name  = "buckets[0].name"
    value = var.bucket_name
  }

  set {
    name  = "buckets[0].policy"
    value = "download" # anonymous read-only
  }

  set {
    name  = "buckets[0].purge"
    value = "false"
  }

  # Disable the chart's bundled ingress; we manage Traefik IngressRoutes below
  # so cert-manager issues certs consistently with the rest of the cluster.
  set {
    name  = "ingress.enabled"
    value = "false"
  }

  set {
    name  = "consoleIngress.enabled"
    value = "false"
  }
}

# --- Ingress: S3 API (the public CDN endpoint) -------------------------------

resource "kubernetes_manifest" "cdn_certificate" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "minio-cdn-tls"
      namespace = "minio"
    }
    spec = {
      secretName = "minio-cdn-tls"
      issuerRef = {
        name = var.certificate_issuer
        kind = "ClusterIssuer"
      }
      dnsNames = [var.cdn_hostname]
    }
  }

  depends_on = [helm_release.minio]
}

resource "kubernetes_manifest" "cdn_ingressroute" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "minio-cdn"
      namespace = "minio"
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [
        {
          match = "Host(`${var.cdn_hostname}`)"
          kind  = "Rule"
          services = [
            {
              name = "minio"
              port = 9000
            }
          ]
        }
      ]
      tls = {
        secretName = "minio-cdn-tls"
      }
    }
  }

  depends_on = [kubernetes_manifest.cdn_certificate]
}

# --- Ingress: MinIO web console (admin) --------------------------------------

resource "kubernetes_manifest" "console_certificate" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "minio-console-tls"
      namespace = "minio"
    }
    spec = {
      secretName = "minio-console-tls"
      issuerRef = {
        name = var.certificate_issuer
        kind = "ClusterIssuer"
      }
      dnsNames = [var.console_hostname]
    }
  }

  depends_on = [helm_release.minio]
}

resource "kubernetes_manifest" "console_ingressroute" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "minio-console"
      namespace = "minio"
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [
        {
          match = "Host(`${var.console_hostname}`)"
          kind  = "Rule"
          services = [
            {
              name = "minio-console"
              port = 9001
            }
          ]
        }
      ]
      tls = {
        secretName = "minio-console-tls"
      }
    }
  }

  depends_on = [kubernetes_manifest.console_certificate]
}
