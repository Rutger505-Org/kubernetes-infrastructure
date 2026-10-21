terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
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

# SeaweedFS: self-hosted, S3-compatible object storage used as a personal CDN
# for sharing clips and hosting build artifacts. It runs on its own VM
# (homelab-infrastructure, host seaweedfs) because the k3s nodes do not
# have the disk for it. This module only puts it behind Traefik:
#   https://cdn.rutgerpronk.com/<bucket>/<file>
#
# A Service without a selector plus a hand-written EndpointSlice points at the
# VM, so the IngressRoute and the cert-manager certificate stay as they were.

resource "kubernetes_namespace" "seaweedfs" {
  metadata {
    name = "seaweedfs"
  }
}

resource "kubernetes_service_v1" "s3" {
  metadata {
    name      = "seaweedfs-s3"
    namespace = kubernetes_namespace.seaweedfs.metadata[0].name
  }

  spec {
    port {
      name        = "s3"
      port        = var.seaweedfs_s3_port
      target_port = var.seaweedfs_s3_port
      protocol    = "TCP"
    }
  }
}

resource "kubernetes_endpoint_slice_v1" "s3" {
  metadata {
    name      = "seaweedfs-s3-vm"
    namespace = kubernetes_namespace.seaweedfs.metadata[0].name
    labels = {
      "kubernetes.io/service-name"             = kubernetes_service_v1.s3.metadata[0].name
      "endpointslice.kubernetes.io/managed-by" = "opentofu"
    }
  }

  address_type = "IPv4"

  # Traefik skips endpoints that are not explicitly ready, and nothing probes a
  # hand-written slice to set it.
  endpoint {
    addresses = [var.seaweedfs_ip]

    condition {
      ready = true
    }
  }

  port {
    name         = "s3"
    port         = var.seaweedfs_s3_port
    protocol     = "TCP"
    app_protocol = "http"
  }
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
              name = kubernetes_service_v1.s3.metadata[0].name
              port = var.seaweedfs_s3_port
            }
          ]
        }
      ]
      tls = {
        secretName = "seaweedfs-cdn-tls"
      }
    }
  }

  depends_on = [kubernetes_endpoint_slice_v1.s3, kubernetes_manifest.cdn_certificate]
}
