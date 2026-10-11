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
    minio = {
      source  = "aminueza/minio"
      version = "3.44.0"
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

provider "minio" {
  minio_server   = var.cdn_hostname
  minio_ssl      = true
  minio_user     = var.root_user
  minio_password = var.root_password
}

# MinIO: self-hosted, S3-compatible object storage used as a personal CDN for
# sharing clips and hosting build artifacts (e.g. the soundboard APK).
#
# Storage is backed by a PersistentVolumeClaim on the node's local disk
# (default 30Gi via the local-path StorageClass); grow it later by bumping
# storage_size and the underlying disk. See homelab-infrastructure for the
# disk-mount step.
#
# Two hostnames are served through Traefik + cert-manager:
#   - cdn.rutgerpronk.com   -> the S3 API (public bucket reads = direct file URLs,
#                              e.g. cdn.rutgerpronk.com/clips/<file>)
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

  # The chart defaults to a 16Gi memory *request*, which won't schedule on a
  # homelab node. A personal CDN needs a fraction of that.
  set {
    name  = "resources.requests.memory"
    value = var.memory_request
  }

  set {
    name  = "resources.limits.memory"
    value = var.memory_limit
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

  # No users or buckets through the chart: its post-install job needs the
  # quay.io/minio/mc image, which MinIO no longer publishes, and the default
  # users list creates a consoleAdmin "console" user with password "console123".
  # Buckets are managed with the minio provider below instead.
  values = [yamlencode({
    users   = []
    buckets = []
  })]

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

# --- Buckets ------------------------------------------------------------------

# One public bucket per use case keeps URLs short
# (cdn.rutgerpronk.com/<bucket>/<file>) and lets each bucket get its own
# lifecycle/versioning later. Anonymous read-only so uploaded files are directly
# linkable (and Discord can preview them).

resource "minio_s3_bucket" "cdn" {
  for_each = toset(var.bucket_names)

  bucket = each.value

  depends_on = [helm_release.minio, kubernetes_manifest.cdn_ingressroute]
}

resource "minio_s3_bucket_anonymous_access" "cdn" {
  for_each = minio_s3_bucket.cdn

  bucket      = each.value.bucket
  access_type = "public-read"
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
