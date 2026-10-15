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
    secret_suffix = "pulse"
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

resource "kubernetes_namespace" "pulse" {
  metadata {
    name = "pulse"
  }
}

resource "helm_release" "pulse" {
  name       = "pulse"
  namespace  = kubernetes_namespace.pulse.metadata[0].name
  repository = "https://rcourtman.github.io/Pulse"
  chart      = "pulse"
  version    = var.pulse_chart_version

  wait    = true
  timeout = 600

  values = [yamlencode({
    # The PVC is ReadWriteOnce, so a rolling update would hang on a
    # Multi-Attach error with the old pod still holding the volume.
    strategy = { type = "Recreate" }

    # LAN only: Caddy on the reverse-proxy VM serves it as
    # https://${var.pulse_hostname}. Local keeps Caddy's address as the client
    # IP, which Pulse needs to trust its forwarded HTTPS headers.
    service = {
      type                  = "LoadBalancer"
      loadBalancerIP        = var.pulse_load_balancer_ip
      externalTrafficPolicy = "Local"
    }

    # Holds the encrypted Proxmox credentials and history. local-path on the
    # node's root disk, not backed up.
    persistence = {
      enabled = true
      size    = "2Gi"
    }

    server = {
      extraEnv = [
        { name = "PULSE_PUBLIC_URL", value = "https://${var.pulse_hostname}" },
        { name = "PULSE_TRUSTED_PROXY_CIDRS", value = var.trusted_proxy_cidrs },
      ]
      resources = {
        requests = { cpu = "50m", memory = "128Mi" }
        limits   = { memory = "512Mi" }
      }
    }
  })]
}
