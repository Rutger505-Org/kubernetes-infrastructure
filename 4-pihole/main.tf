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
    secret_suffix = "pihole"
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

resource "kubernetes_namespace" "pihole" {
  metadata {
    name = "pihole"
  }
}

resource "helm_release" "pihole" {
  name       = "pihole"
  repository = "https://mojo2600.github.io/pihole-kubernetes/"
  chart      = "pihole"
  namespace  = kubernetes_namespace.pihole.metadata[0].name
  version    = "2.35.0"

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

      adminPassword = var.admin_password
    })
  ]

  depends_on = [kubernetes_namespace.pihole]
}
