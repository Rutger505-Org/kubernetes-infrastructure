terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.1.1"
    }
  }

  backend "kubernetes" {
    config_path   = "~/.kube/config"
    secret_suffix = "pihole"
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

resource "helm_release" "pihole" {
  name       = "pihole"
  repository = "https://mojo2600.github.io/pihole-kubernetes/"
  chart      = "pihole"
  version    = "2.35.0"

  namespace        = "pihole"
  create_namespace = true

  recreate_pods = true

  set_sensitive = [ {
    name = "adminPassword"
    value = var.admin_password
  } ]

  values = [
    yamlencode({
      persistentVolumeClaim = {
        enabled          = true
        size             = "2Gi"
        storageClassName = "local-path"
      }

      serviceWeb = {
        type           = "LoadBalancer"
        annotations = {
          "metallb.io/allow-shared-ip" = "pihole-svc"
          "metallb.io/loadBalancerIPs" = var.pihole_ip
        }
      }

      serviceDns = {
        type           = "LoadBalancer"
        annotations = {
          "metallb.io/allow-shared-ip" = "pihole-svc"
          "metallb.io/loadBalancerIPs" = var.pihole_ip
        }
      }

      serviceDhcp = {
        enabled = true
        type           = "LoadBalancer"
        annotations = {
          "metallb.io/allow-shared-ip" = "pihole-svc"
          "metallb.io/loadBalancerIPs" = var.pihole_ip
        }
      }

      ingress = {
        enabled = false
      }

    })
  ]
}
