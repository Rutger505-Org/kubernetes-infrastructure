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
    secret_suffix = "minecraft"
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

# Minecraft (Vault Hunters Third Edition) behind mc-router.
#
# Traffic path:
#   player -> mc-vault.rutgerpronk.com:25565 -> router port-forward
#     -> MetalLB IP (router_ip) -> mc-router -> minecraft Service -> pod
#
# mc-router reads the Minecraft handshake hostname and looks up a Service
# annotated with mc-router.itzg.me/externalServerName, so one public port can
# serve several servers later on.
#
# Auto-sleep: mc-router scales the server StatefulSet to 0 after
# idle_shutdown_after without connections, and back to 1 when someone connects.
# That is why the server runs as a StatefulSet — mc-router's scaler only
# handles that kind.

resource "kubernetes_namespace" "minecraft" {
  metadata {
    name = "minecraft"
  }
}

# CurseForge key lives in its own Secret so the value can be replaced later
# without touching the Helm release. A placeholder is harmless while
# server_type is VANILLA.
resource "kubernetes_secret" "curseforge" {
  metadata {
    name      = "curseforge-api-key"
    namespace = kubernetes_namespace.minecraft.metadata[0].name
  }

  data = {
    "cf-api-key" = var.curseforge_api_key
  }
}

resource "helm_release" "mc_router" {
  name       = "mc-router"
  repository = "https://itzg.github.io/minecraft-server-charts/"
  chart      = "mc-router"
  namespace  = kubernetes_namespace.minecraft.metadata[0].name
  version    = "1.5.0"

  wait    = true
  timeout = 600

  set {
    name  = "services.minecraft.type"
    value = "LoadBalancer"
  }

  set {
    name  = "services.minecraft.port"
    value = "25565"
  }

  set {
    name  = "services.minecraft.loadBalancerIP"
    value = var.router_ip
  }

  # Wake a sleeping server when a player connects.
  set {
    name  = "minecraftRouter.autoScale.up.enabled"
    value = "true"
  }

  # Put it back to sleep once nobody is connected.
  set {
    name  = "minecraftRouter.autoScale.down.enabled"
    value = "true"
  }

  set {
    name  = "minecraftRouter.autoScale.down.after"
    value = var.idle_shutdown_after
  }

  set {
    name  = "minecraftRouter.debug.enabled"
    value = "true"
  }
}

resource "helm_release" "minecraft" {
  name       = "vault-hunters"
  repository = "https://itzg.github.io/minecraft-server-charts/"
  chart      = "minecraft"
  namespace  = kubernetes_namespace.minecraft.metadata[0].name
  version    = "5.2.0"

  # A modded first boot downloads the whole pack; don't block the pipeline on it.
  wait    = false
  timeout = 900

  # mc-router's scaler only supports StatefulSets.
  set {
    name  = "workloadAsStatefulSet"
    value = "true"
  }

  # RollingUpdate so a changed pod template (resources, server type) actually
  # replaces the running pod; OnDelete left a stale Pending pod behind.
  set {
    name  = "strategyType"
    value = "RollingUpdate"
  }

  # Pinned to the node with the memory for a modded server.
  set {
    name  = "nodeSelector.kubernetes\\.io/hostname"
    value = var.node_hostname
  }

  # How mc-router discovers this server.
  set {
    name  = "serviceAnnotations.mc-router\\.itzg\\.me/externalServerName"
    value = var.hostname
  }

  set {
    name  = "minecraftServer.eula"
    value = "TRUE"
  }

  set {
    name  = "minecraftServer.type"
    value = var.server_type
  }

  set {
    name  = "minecraftServer.version"
    value = var.minecraft_version
  }

  set {
    name  = "minecraftServer.memory"
    value = var.server_memory
  }

  set {
    name  = "minecraftServer.motd"
    value = var.motd
  }

  set {
    name  = "minecraftServer.difficulty"
    value = var.difficulty
  }

  set {
    name  = "minecraftServer.maxPlayers"
    value = var.max_players
  }

  set {
    name  = "minecraftServer.ops"
    value = var.ops
  }

  # The server must stay reachable through mc-router only.
  set {
    name  = "minecraftServer.serviceType"
    value = "ClusterIP"
  }

  # CurseForge modpack settings; only consulted when type is AUTO_CURSEFORGE.
  set {
    name  = "minecraftServer.autoCurseForge.apiKey.existingSecret"
    value = kubernetes_secret.curseforge.metadata[0].name
  }

  set {
    name  = "minecraftServer.autoCurseForge.apiKey.secretKey"
    value = "cf-api-key"
  }

  set {
    name  = "minecraftServer.autoCurseForge.slug"
    value = var.curseforge_slug
  }

  set {
    name  = "minecraftServer.autoCurseForge.fileId"
    value = var.curseforge_file_id
  }

  # World and mods survive the auto-sleep scale-down and any modpack switch.
  set {
    name  = "persistence.dataDir.enabled"
    value = "true"
  }

  set {
    name  = "persistence.dataDir.Size"
    value = var.storage_size
  }

  set {
    name  = "persistence.storageClass"
    value = var.storage_class
  }

  set {
    name  = "resources.requests.memory"
    value = var.memory_request
  }

  set {
    name  = "resources.requests.cpu"
    value = var.cpu_request
  }

  set {
    name  = "resources.limits.memory"
    value = var.memory_limit
  }

  depends_on = [helm_release.mc_router]
}
