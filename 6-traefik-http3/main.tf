terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }

  backend "kubernetes" {
    config_path   = "~/.kube/config"
    secret_suffix = "traefik-http3"
  }
}

provider "kubernetes" {
  config_path = "~/.kube/config"
}

# Traefik is installed by k3s itself through the packaged HelmChart in kube-system.
# A HelmChartConfig with the same name is merged into that chart's values by the
# k3s helm-controller, which is the supported way to change Traefik settings
# without taking ownership of the chart away from k3s.
#
# This turns on http3 for the websecure entrypoint: Traefik then listens on
# UDP/8443 (QUIC) inside the pod and advertises it with the Alt-Svc header.
#
# It also owns the LoadBalancer address of the traefik Service. That has to live
# in the chart values rather than in a kubectl patch: the MetalLB pool has
# autoAssign = false, so a Service without an explicit loadBalancerIP gets no
# address at all the moment helm re-renders it.
resource "kubernetes_manifest" "traefik_http3" {
  manifest = {
    apiVersion = "helm.cattle.io/v1"
    kind       = "HelmChartConfig"
    metadata = {
      name      = "traefik"
      namespace = "kube-system"
    }
    spec = {
      valuesContent = yamlencode({
        ports = {
          websecure = {
            http3 = {
              enabled        = true
              advertisedPort = var.advertised_port
            }
          }
        }
        service = {
          annotations = {
            "metallb.io/allow-shared-ip" = local.shared_ip_key
          }
          spec = {
            loadBalancerIP = var.traefik_ip
          }
        }
      })
    }
  }
}

# One-time migration away from the kubectl patch this module used before
# (PRs #51 and #52): that patch added a websecure-http3/UDP port to the
# helm-owned traefik Service. MetalLB refuses to share one address between two
# Services that expose the same port and protocol, so the patched port has to go
# before traefik-http3 can claim the address.
#
# The chart itself never renders that port in this cluster, so this runs once and
# then stays a no-op. It is kept rather than run by hand so the module also
# repairs the situation if a future chart upgrade starts adding the port again,
# which would otherwise silently break the shared IP.
resource "null_resource" "remove_patched_udp_port" {
  triggers = {
    migration = "remove-patched-udp-port-v1"
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -eu

      SERVICE=$(kubectl get service traefik -n kube-system -o json)

      if ! echo "$SERVICE" | jq -e '.spec.ports[] | select(.name == "websecure-http3")' >/dev/null; then
        echo "traefik service has no patched websecure-http3 port, nothing to undo"
        exit 0
      fi

      PORTS=$(echo "$SERVICE" | jq -c '[.spec.ports[] | select(.name != "websecure-http3")]')

      kubectl patch service traefik -n kube-system --type=merge -p "{\"spec\":{\"ports\":$PORTS}}"
    EOT
  }

  depends_on = [kubernetes_manifest.traefik_http3]
}

# The chart is supposed to add the UDP port to the traefik Service by itself once
# http3 is enabled, but the chart bundled with this k3s release does not: helm
# renders a Service with only web/TCP and websecure/TCP, while the very same
# chart version rendered outside the cluster does produce the UDP port. Rather
# than patching a helm-owned object from a provisioner, the UDP entrypoint is
# exposed as its own Service that this module fully owns.
#
# Both Services carry the same metallb.io/allow-shared-ip key and the same
# address, which is what lets MetalLB hand out one IP for TCP/443 and UDP/443.
#
# targetPort is the *numeric* container port on purpose. A named targetPort only
# resolves to a containerPort with a matching protocol, and the Traefik pod only
# declares websecure as TCP, so the named form silently blackholes every QUIC
# packet while the Service still looks perfectly healthy.
resource "kubernetes_service" "traefik_http3" {
  metadata {
    name      = "traefik-http3"
    namespace = "kube-system"

    annotations = {
      "metallb.io/allow-shared-ip" = local.shared_ip_key
    }

    labels = {
      "app.kubernetes.io/name"       = "traefik"
      "app.kubernetes.io/instance"   = "traefik-kube-system"
      "app.kubernetes.io/managed-by" = "OpenTofu"
    }
  }

  spec {
    type             = "LoadBalancer"
    load_balancer_ip = var.traefik_ip

    selector = {
      "app.kubernetes.io/name"     = "traefik"
      "app.kubernetes.io/instance" = "traefik-kube-system"
    }

    port {
      name        = "websecure-http3"
      protocol    = "UDP"
      port        = var.advertised_port
      target_port = var.websecure_container_port
    }
  }

  depends_on = [
    kubernetes_manifest.traefik_http3,
    null_resource.remove_patched_udp_port,
  ]
}
