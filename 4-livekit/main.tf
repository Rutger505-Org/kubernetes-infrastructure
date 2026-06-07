terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
  }

  backend "kubernetes" {
    config_path   = "~/.kube/config"
    secret_suffix = "livekit"
  }
}

provider "kubernetes" {
  config_path = "~/.kube/config"
}

locals {
  signaling_host = "livekit.${var.base_domain}"

  # LiveKit server config. The SFU relays all media, so calls are never
  # peer-to-peer. Signaling (7880) is fronted by traefik/TLS; media uses a
  # single muxed TCP port (7881) and UDP port (7882) exposed via MetalLB.
  livekit_yaml = yamlencode({
    port = 7880
    rtc = {
      tcp_port        = 7881
      udp_port        = 7882
      use_external_ip = true
    }
    keys = {
      (var.api_key) = var.api_secret
    }
  })
}

resource "kubernetes_namespace" "livekit" {
  metadata {
    name = "livekit"
  }
}

# Config (including keys) as a Secret since it contains the API secret.
resource "kubernetes_secret" "livekit" {
  metadata {
    name      = "livekit-config"
    namespace = kubernetes_namespace.livekit.metadata[0].name
  }

  data = {
    "livekit.yaml" = local.livekit_yaml
  }
}

resource "kubernetes_deployment" "livekit" {
  metadata {
    name      = "livekit-server"
    namespace = kubernetes_namespace.livekit.metadata[0].name
  }

  # Don't block apply on rollout health; media networking is environment
  # specific and is verified out-of-band with real clients.
  wait_for_rollout = false

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "livekit-server"
      }
    }

    template {
      metadata {
        labels = {
          app = "livekit-server"
        }
        annotations = {
          "config-hash" = sha1(local.livekit_yaml)
        }
      }

      spec {
        container {
          name  = "livekit-server"
          image = var.image
          args  = ["--config", "/etc/livekit/livekit.yaml"]

          port {
            name           = "signaling"
            container_port = 7880
          }
          port {
            name           = "rtc-tcp"
            container_port = 7881
          }
          port {
            name           = "rtc-udp"
            container_port = 7882
            protocol       = "UDP"
          }

          volume_mount {
            name       = "config"
            mount_path = "/etc/livekit"
            read_only  = true
          }
        }

        volume {
          name = "config"
          secret {
            secret_name = kubernetes_secret.livekit.metadata[0].name
          }
        }
      }
    }
  }
}

# Signaling service (ws) behind traefik + TLS.
resource "kubernetes_service" "signaling" {
  metadata {
    name      = "livekit-signaling"
    namespace = kubernetes_namespace.livekit.metadata[0].name
  }

  spec {
    selector = {
      app = "livekit-server"
    }
    port {
      name        = "signaling"
      port        = 80
      target_port = 7880
    }
    type = "ClusterIP"
  }
}

# Media service (RTC) exposed directly on the LAN via MetalLB. Clients reach
# the SFU here; this IP/ports must be reachable from where users connect (e.g.
# port-forwarded on the router for internet clients).
resource "kubernetes_service" "media" {
  metadata {
    name      = "livekit-media"
    namespace = kubernetes_namespace.livekit.metadata[0].name
  }

  spec {
    selector = {
      app = "livekit-server"
    }
    port {
      name        = "rtc-tcp"
      port        = 7881
      target_port = 7881
      protocol    = "TCP"
    }
    port {
      name        = "rtc-udp"
      port        = 7882
      target_port = 7882
      protocol    = "UDP"
    }
    type = "LoadBalancer"
  }
}

resource "kubernetes_ingress_v1" "signaling" {
  metadata {
    name      = "livekit-signaling"
    namespace = kubernetes_namespace.livekit.metadata[0].name
  }

  spec {
    ingress_class_name = "traefik"

    tls {
      hosts       = [local.signaling_host]
      secret_name = "livekit-tls"
    }

    rule {
      host = local.signaling_host
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.signaling.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_manifest" "certificate" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "livekit-certificate"
      namespace = kubernetes_namespace.livekit.metadata[0].name
    }
    spec = {
      secretName  = "livekit-tls"
      duration    = "2160h"
      renewBefore = "360h"
      dnsNames    = [local.signaling_host]
      issuerRef = {
        name = var.certificate_issuer
        kind = "ClusterIssuer"
      }
    }
  }
}

output "signaling_url" {
  description = "Set this as LIVEKIT_URL for apps."
  value       = "wss://${local.signaling_host}"
}
