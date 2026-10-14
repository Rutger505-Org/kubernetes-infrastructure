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

# The chart does render websecure-http3/UDP/443 (helm template shows it), but it
# never survives into the cluster: Kubernetes merges Service ports, and container
# ports, by port number only, ignoring the protocol. Helm's strategic-merge patch
# therefore folds the UDP/443 entry into the TCP/443 one. That is why
# "helm get manifest" looked fine while the Service and pod had no UDP port.
#
# So the Service's port list is set here, in full, with a JSON merge patch that
# replaces the whole list instead of merging by port number.
#
# ORDER MATTERS. On the old cluster the HelmChartConfig had been rolled out long
# before this patch existed. On a fresh cluster both land in the same apply: the
# patch ran one second before helm-controller's upgrade, which then merged the
# chart's UDP entry onto the patched list and left websecure/TCP/443 pointing at
# targetPort "websecure-http3", a port the pod does not have, so all HTTPS was
# refused. Hence: wait until helm-controller has rolled Traefik out with http3,
# then write the list.
#
# The list is written in full so the TCP ports are repaired too, not only the UDP
# one. targetPort of the UDP port must be the *numeric* container port: a named
# targetPort only resolves to a containerPort with a matching protocol, and the
# pod only declares websecure as TCP. Allocated nodePorts are kept.
#
# Runs on every apply (no-op when the Service already matches), so a later helm
# upgrade, e.g. a k3s version bump, that mangles the ports again is repaired by
# the next deploy or a workflow_dispatch.
resource "null_resource" "traefik_http3_service_port" {
  triggers = {
    always = timestamp()
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      DESIRED_PORTS = jsonencode([
        { name = "web", port = 80, protocol = "TCP", targetPort = "web" },
        { name = "websecure", port = 443, protocol = "TCP", targetPort = "websecure" },
        { name = "websecure-http3", port = var.advertised_port, protocol = "UDP", targetPort = var.websecure_container_port },
      ])
    }
    command = <<-EOT
      set -eu

      # helm-controller applies the HelmChartConfig asynchronously in a job.
      for i in $(seq 60); do
        if kubectl get deployment traefik -n kube-system -o jsonpath='{.spec.template.spec.containers[0].args}' | grep -q 'entryPoints.websecure.http3'; then
          break
        fi
        if [ "$i" = 60 ]; then
          echo "helm-controller did not roll out http3 on the traefik Deployment within 5 minutes" >&2
          exit 1
        fi
        sleep 5
      done
      kubectl rollout status deployment/traefik -n kube-system --timeout=5m

      SERVICE=$(kubectl get service traefik -n kube-system -o json)

      DESIRED=$(echo "$SERVICE" | jq -c --argjson want "$DESIRED_PORTS" '.spec.ports as $cur | $want | map(. as $p | . + ([$cur[] | select(.port == $p.port and .protocol == $p.protocol) | {nodePort}] | first // {}))')

      if [ "$(echo "$SERVICE" | jq -cS '.spec.ports')" = "$(echo "$DESIRED" | jq -cS '.')" ]; then
        echo "traefik service ports already correct, nothing to do"
        exit 0
      fi

      echo "fixing traefik service ports: $(echo "$SERVICE" | jq -c '.spec.ports') -> $DESIRED"
      kubectl patch service traefik -n kube-system --type=merge -p "{\"spec\":{\"ports\":$DESIRED}}"
    EOT
  }

  depends_on = [kubernetes_manifest.traefik_http3]
}
