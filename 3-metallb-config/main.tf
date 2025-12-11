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
    secret_suffix = "metallb-config"
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


# MetalLB Helm chart is installed in 2-metallb folder
# This configuration only manages the IPAddressPool and L2Advertisement

resource "kubernetes_manifest" "ip_address_pool" {
  manifest = {
    apiVersion = "metallb.io/v1beta1"
    kind       = "IPAddressPool"
    metadata = {
      name      = "default"
      namespace = "metallb-system"
    }
    spec = {
      addresses = var.ip_addresses
    }
  }
}

resource "kubernetes_manifest" "l2_advertisement" {
  manifest = {
    apiVersion = "metallb.io/v1beta1"
    kind       = "L2Advertisement"
    metadata = {
      name      = "default"
      namespace = "metallb-system"
    }
    spec = {
      ipAddressPools = ["default"]
    }
  }
}

resource "null_resource" "traefik_loadbalancer" {
  triggers = {
    traefik_ip = var.traefik_ip
  }

  provisioner "local-exec" {
    command = <<-EOT
      kubectl patch service traefik -n kube-system -p '{"spec":{"type":"LoadBalancer","loadBalancerIP":"${var.traefik_ip}"}}'
    EOT
  }

  depends_on = [kubernetes_manifest.ip_address_pool]
}
