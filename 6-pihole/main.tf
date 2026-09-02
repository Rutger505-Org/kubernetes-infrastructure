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

# Pi-hole: network-wide DNS sinkhole / ad-blocker for the home LAN.
#
# The router points its primary DNS at the DNS service's LoadBalancer IP, so
# every device on the network resolves through Pi-hole. Both services get a
# fixed MetalLB address from the pool (defined in 3-metallb-config):
#   - dns_ip (.231) -> DNS on port 53 (TCP + UDP, mixed service)
#   - web_ip (.232) -> admin web UI, kept LAN-only (no public hostname/TLS)
#
# Config and the gravity/adlist database persist on a local-path PVC.
# DHCP stays disabled: the router remains the DHCP server.

resource "helm_release" "pihole" {
  name             = "pihole"
  repository       = "https://mojo2600.github.io/pihole-kubernetes/"
  chart            = "pihole"
  namespace        = "pihole"
  create_namespace = true
  version          = "2.38.0"

  wait    = true
  timeout = 600

  # Single replica: the chart mounts one ReadWriteOnce local-path PVC holding
  # the gravity/adlist SQLite DB. Extra replicas are pinned to the same node by
  # the volume's node affinity and would contend on that database.
  set {
    name  = "replicaCount"
    value = "1"
  }

  # --- DNS service (.231): mixed TCP+UDP on port 53 via MetalLB -------------
  set {
    name  = "serviceDns.type"
    value = "LoadBalancer"
  }

  set {
    name  = "serviceDns.mixedService"
    value = "true"
  }

  set {
    name  = "serviceDns.loadBalancerIP"
    value = var.dns_ip
  }

  # --- Web UI service (.232): LAN-only, no ingress/TLS ----------------------
  set {
    name  = "serviceWeb.type"
    value = "LoadBalancer"
  }

  set {
    name  = "serviceWeb.loadBalancerIP"
    value = var.web_ip
  }

  # Router is the DHCP server; Pi-hole only does DNS.
  set {
    name  = "serviceDhcp.enabled"
    value = "false"
  }

  # Admin password from CI secret.
  set_sensitive {
    name  = "adminPassword"
    value = var.web_password
  }

  # Upstream resolvers.
  set {
    name  = "DNS1"
    value = var.upstream_dns_1
  }

  set {
    name  = "DNS2"
    value = var.upstream_dns_2
  }

  # Persist /etc/pihole + /etc/dnsmasq.d on the node's local disk.
  set {
    name  = "persistentVolumeClaim.enabled"
    value = "true"
  }

  set {
    name  = "persistentVolumeClaim.size"
    value = var.storage_size
  }

  set {
    name  = "persistentVolumeClaim.storageClass"
    value = var.storage_class
  }
}
