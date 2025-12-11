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
  version    = "2.19.0"

  values = [
    yamlencode({
      replicaCount = 2

      persistentVolumeClaim = {
        enabled          = true
        size             = "2Gi"
        storageClassName = "local-path"
      }

      serviceWeb = {
        type           = "LoadBalancer"
        loadBalancerIP = var.pihole_web_ip
        annotations = {
          "metallb.universe.tf/ip-allocated-from-pool" = "default"
        }
      }

      serviceDns = {
        type           = "LoadBalancer"
        loadBalancerIP = var.pihole_dns_ip
        annotations = {
          "metallb.universe.tf/ip-allocated-from-pool" = "default"
          "metallb.universe.tf/allow-shared-ip"        = "pihole-dns"
        }
      }

      ingress = {
        enabled = false
      }

      adminPassword = var.admin_password

      adlists = [
        # StevenBlack's Unified hosts - Popular unified hosts file with ads, malware, and trackers
        "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts",
        # AdGuard DNS filter - Comprehensive ad blocking list
        "https://v.firebog.net/hosts/AdguardDns.txt",
        # Admiral - Anti-adblock adlist
        "https://v.firebog.net/hosts/Admiral.txt",
        # EasyList - Primary ad blocking list
        "https://v.firebog.net/hosts/Easylist.txt",
        # Prigent Ads - French ads blocking list
        "https://v.firebog.net/hosts/Prigent-Ads.txt",
        # Malicious URLs - Malware protection
        "https://v.firebog.net/hosts/Prigent-Malware.txt",
        # Phishing URLs - Phishing protection
        "https://v.firebog.net/hosts/Prigent-Phishing.txt",
      ]
    })
  ]

  depends_on = [kubernetes_namespace.pihole]
}
