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
        # With the chart default (service.single = false) the UDP/443 port is
        # rendered into a *separate* "traefik-udp" Service, which would need a
        # second MetalLB address or a shared-IP annotation. Switching to a single
        # Service keeps TCP/443 and UDP/443 on the same LoadBalancer IP.
        service = {
          single = true
          spec = {
            loadBalancerIP = var.traefik_ip
          }
        }
      })
    }
  }
}

# The chart's own UDP port never materialised in this cluster: the Service in the
# deployed release only contains web/TCP and websecure/TCP, even though
# "helm get values traefik" shows service.single = true and Traefik itself runs
# with --entryPoints.websecure.http3. Rendering the same chart version
# (37.1.1+up37.1.0) with the same values locally *does* produce the UDP port, so
# the chart bundled on the node behaves differently than the published one.
#
# So the UDP port is added to the Service here, in the same style as the
# loadBalancerIP patch in 3-metallb-config.
#
# targetPort must be the *numeric* container port, not the named port
# "websecure": a named targetPort only resolves to a containerPort with a
# matching protocol, and the Traefik pod only declares websecure as TCP. With the
# name, kube-proxy has nowhere to send the UDP packets and every QUIC handshake
# times out while the Service still looks correct.
#
# The patch rebuilds the desired port list, keeps allocated nodePorts and is a
# no-op once the Service already matches, so it can run on every deploy.
resource "null_resource" "traefik_http3_service_port" {
  triggers = {
    advertised_port = var.advertised_port
    target_port     = var.websecure_container_port
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -eu

      SERVICE=$(kubectl get service traefik -n kube-system -o json)

      DESIRED=$(echo "$SERVICE" | jq -c --argjson p ${var.advertised_port} --argjson t ${var.websecure_container_port} '[.spec.ports[] | select(.name != "websecure-http3")] + [{name: "websecure-http3", protocol: "UDP", port: $p, targetPort: $t} + ([.spec.ports[] | select(.name == "websecure-http3") | {nodePort}] | first // {})]')

      if [ "$(echo "$SERVICE" | jq -cS '.spec.ports')" = "$(echo "$DESIRED" | jq -cS '.')" ]; then
        echo "traefik service already exposes websecure-http3 correctly, nothing to do"
        exit 0
      fi

      kubectl patch service traefik -n kube-system --type=merge -p "{\"spec\":{\"ports\":$DESIRED}}"
    EOT
  }

  depends_on = [kubernetes_manifest.traefik_http3]
}
