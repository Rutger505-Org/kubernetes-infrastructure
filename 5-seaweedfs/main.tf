terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
    helm = {
      source = "hashicorp/helm"
      # 3.x embeds Helm 3.20; the 2.x line (Helm 3.15) lacks fromToml, which
      # the SeaweedFS chart uses.
      version = "~> 3.3"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  backend "kubernetes" {
    config_path   = "~/.kube/config"
    secret_suffix = "seaweedfs"
  }
}

provider "kubernetes" {
  config_path = "~/.kube/config"
}

provider "helm" {
  kubernetes = {
    config_path = "~/.kube/config"
  }
}

# SeaweedFS: self-hosted, S3-compatible object storage used as a personal CDN
# for sharing clips and hosting build artifacts. Runs as a single all-in-one pod
# (master, volume, filer and S3 gateway in one process).
#
# Only the S3 gateway is exposed, on cdn.rutgerpronk.com. Buckets are publicly
# readable per object, but anonymous listing and writes are denied:
#   https://cdn.rutgerpronk.com/<bucket>/<file>

resource "kubernetes_namespace" "seaweedfs" {
  metadata {
    name = "seaweedfs"
  }
}

resource "random_password" "s3_access_key" {
  for_each = toset(["admin", "read"])
  length   = 20
  special  = false
}

resource "random_password" "s3_secret_key" {
  for_each = toset(["admin", "read"])
  length   = 40
  special  = false
}

# Generated here instead of by the chart: the chart's own generation uses
# Helm's lookup, which renders fresh random keys on every plan.
resource "kubernetes_secret" "s3_credentials" {
  metadata {
    name      = "seaweedfs-s3-credentials"
    namespace = kubernetes_namespace.seaweedfs.metadata[0].name
  }

  data = {
    admin_access_key_id     = random_password.s3_access_key["admin"].result
    admin_secret_access_key = random_password.s3_secret_key["admin"].result
    read_access_key_id      = random_password.s3_access_key["read"].result
    read_secret_access_key  = random_password.s3_secret_key["read"].result
  }
}

resource "helm_release" "seaweedfs" {
  name       = "seaweedfs"
  repository = "https://seaweedfs.github.io/seaweedfs/helm"
  chart      = "seaweedfs"
  namespace  = kubernetes_namespace.seaweedfs.metadata[0].name
  version    = "4.48.0"

  wait    = true
  timeout = 600

  values = [yamlencode({
    master = { enabled = false }
    volume = { enabled = false }
    filer  = { enabled = false }

    s3 = {
      credentials = {
        admin = { existingSecret = kubernetes_secret.s3_credentials.metadata[0].name }
        read  = { existingSecret = kubernetes_secret.s3_credentials.metadata[0].name }
      }
    }

    allInOne = {
      enabled = true

      s3 = {
        enabled = true
        # Without auth the gateway accepts anonymous writes.
        enableAuth = true
        createBuckets = [for name in var.bucket_names : {
          name          = name
          anonymousRead = true
        }]
      }

      data = {
        type         = "persistentVolumeClaim"
        size         = var.storage_size
        storageClass = var.storage_class
      }

      # The chart defaults (1Gi request, 2Gi limit) are sized for real
      # clusters; idle it uses well under 100Mi.
      resources = {
        requests = { cpu = "50m", memory = var.memory_request }
        limits   = { memory = var.memory_limit }
      }
    }
  })]
}

resource "kubernetes_manifest" "cdn_certificate" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "seaweedfs-cdn-tls"
      namespace = kubernetes_namespace.seaweedfs.metadata[0].name
    }
    spec = {
      secretName = "seaweedfs-cdn-tls"
      issuerRef = {
        name = var.certificate_issuer
        kind = "ClusterIssuer"
      }
      dnsNames = [var.cdn_hostname]
    }
  }
}

resource "kubernetes_manifest" "cdn_ingressroute" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "seaweedfs-cdn"
      namespace = kubernetes_namespace.seaweedfs.metadata[0].name
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [
        {
          match = "Host(`${var.cdn_hostname}`)"
          kind  = "Rule"
          services = [
            {
              name = "seaweedfs-all-in-one"
              port = 8333
            }
          ]
        }
      ]
      tls = {
        secretName = "seaweedfs-cdn-tls"
      }
    }
  }

  depends_on = [helm_release.seaweedfs, kubernetes_manifest.cdn_certificate]
}
