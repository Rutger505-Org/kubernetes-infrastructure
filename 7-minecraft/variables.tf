variable "hostname" {
  description = "Public hostname players connect to. mc-router routes on this name (Minecraft handshake host), so multiple servers can share one port."
  type        = string
  default     = "mc-vault.rutgerpronk.com"
}

variable "router_ip" {
  description = "Fixed MetalLB LoadBalancer IP for mc-router on port 25565. Must be in the pool from 3-metallb-config and port-forwarded on the router."
  type        = string
}

variable "node_hostname" {
  description = "Node the Minecraft server is pinned to (kubernetes.io/hostname). The lade-pc node has the memory for a modded server."
  type        = string
  default     = "k3s-1"
}

variable "idle_shutdown_after" {
  description = "How long mc-router waits without connections before scaling the server StatefulSet to 0."
  type        = string
  default     = "1h"
}

variable "server_type" {
  description = "itzg/minecraft-server TYPE. AUTO_CURSEFORGE downloads the Vault Hunters Third Edition modpack using the image's baked-in CurseForge API key."
  type        = string
  default     = "AUTO_CURSEFORGE"
}

variable "image_tag" {
  description = "itzg/minecraft-server image tag. Pinned to java17 because Forge 40.x (Minecraft 1.18.2) fails on newer JVMs."
  type        = string
  default     = "java17"
}

variable "minecraft_version" {
  description = "Minecraft version. Ignored for AUTO_CURSEFORGE, which takes the version from the modpack."
  type        = string
  default     = "LATEST"
}

variable "curseforge_slug" {
  description = "CurseForge modpack slug, e.g. vault-hunters-1-18-2 for Vault Hunters Third Edition."
  type        = string
  default     = "vault-hunters-1-18-2"
}

variable "curseforge_file_id" {
  description = "Optional exact CurseForge modpack file id. Empty means newest."
  type        = string
  default     = ""
}

variable "server_memory" {
  description = "JVM heap for the Minecraft server."
  type        = string
  default     = "6G"
}

variable "memory_request" {
  description = "Pod memory request. Keep above the JVM heap to leave room for the JVM's own overhead."
  type        = string
  default     = "8Gi"
}

variable "memory_limit" {
  description = "Pod memory limit."
  type        = string
  default     = "10Gi"
}

variable "cpu_request" {
  description = "Pod CPU request."
  type        = string
  default     = "1"
}

variable "storage_size" {
  description = "Size of the world/mods PVC. Vault Hunters plus a world needs well over 10Gi."
  type        = string
  default     = "30Gi"
}

variable "storage_class" {
  description = "StorageClass for the Minecraft PVC."
  type        = string
  default     = "local-path"
}

variable "ops" {
  description = "Comma-separated player names granted operator."
  type        = string
  default     = ""
}

variable "motd" {
  description = "Server list message."
  type        = string
  default     = "Vault Hunters on Kubernetes"
}

variable "difficulty" {
  description = "Server difficulty."
  type        = string
  default     = "normal"
}

variable "max_players" {
  description = "Maximum concurrent players."
  type        = string
  default     = "10"
}

variable "probe_period_seconds" {
  description = "Seconds between mc-health polls for the startup, readiness and liveness probes."
  type        = string
  default     = "5"
}

variable "startup_failure_threshold" {
  description = "Failed mc-health polls tolerated during boot before the pod is restarted. 200 polls at 5s covers a modded pack download plus world generation."
  type        = string
  default     = "200"
}

variable "readiness_initial_delay_seconds" {
  description = "Seconds before the first readiness poll."
  type        = string
  default     = "10"
}

variable "readiness_failure_threshold" {
  description = "Failed mc-health polls before the pod leaves the Service endpoints."
  type        = string
  default     = "200"
}

variable "liveness_failure_threshold" {
  description = "Failed mc-health polls before an already-started server is restarted."
  type        = string
  default     = "5"
}
