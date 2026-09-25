terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
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
# Enabling http3 on the websecure entrypoint makes Traefik listen on UDP/443
# (QUIC) and advertise it through the Alt-Svc response header. The Traefik
# chart adds the UDP port to the existing traefik Service, so MetalLB keeps
# serving both TCP and UDP from the same LoadBalancer IP.
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
          spec = {
            loadBalancerIP = var.traefik_ip
          }
        }
      })
    }
  }
}
