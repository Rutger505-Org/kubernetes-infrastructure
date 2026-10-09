variable "discord_webhook_url" {
  description = "Discord channel webhook URL that Alertmanager posts alerts to"
  type        = string
  sensitive   = true
}

variable "watchdog_ping_url" {
  description = "Optional dead man's switch URL (e.g. healthchecks.io) pinged every minute by the always-firing Watchdog alert. Empty disables it."
  type        = string
  sensitive   = true
  default     = ""
}

variable "grafana_admin_password" {
  description = "Grafana admin password"
  type        = string
  sensitive   = true
}

variable "grafana_ip" {
  description = "MetalLB LoadBalancer IP for Grafana. LAN/Tailscale only; the pool has autoAssign = false so this must be set explicitly."
  type        = string
  default     = "192.168.178.234"
}

variable "proxmox_token_user" {
  description = "Proxmox user owning the API token"
  type        = string
  default     = "prometheus@pve"
}

variable "proxmox_token_name" {
  description = "Proxmox API token name (the part after '!')"
  type        = string
  default     = "monitoring"
}

variable "proxmox_token_value" {
  description = "Proxmox API token secret, created for a user with the read-only PVEAuditor role"
  type        = string
  sensitive   = true
}

variable "proxmox_verify_ssl" {
  description = "Verify the Proxmox API certificate. False by default because Proxmox ships a self-signed certificate."
  type        = bool
  default     = false
}

variable "proxmox_targets" {
  description = "Proxmox API endpoints to scrape, as host:port"
  type        = list(string)
  default = [
    "192.168.178.200:8006",
    "192.168.178.199:8006",
  ]
}

variable "probe_targets" {
  description = "URLs blackbox-exporter probes over HTTP; each must answer 2xx (redirects are followed)"
  type        = list(string)
  default = [
    "https://rutgerpronk.com",
    "https://cdn.rutgerpronk.com/minio/health/live",
  ]
}

variable "prometheus_retention" {
  description = "How long Prometheus keeps samples"
  type        = string
  default     = "30d"
}

variable "prometheus_storage_size" {
  description = "Size of the Prometheus persistent volume"
  type        = string
  default     = "20Gi"
}

variable "prometheus_memory_request" {
  description = "Prometheus pod memory request"
  type        = string
  default     = "512Mi"
}

variable "prometheus_memory_limit" {
  description = "Prometheus pod memory limit"
  type        = string
  default     = "1Gi"
}

variable "storage_class" {
  description = "StorageClass backing the monitoring PVCs"
  type        = string
  default     = "local-path"
}

variable "kube_prometheus_stack_version" {
  description = "kube-prometheus-stack chart version"
  type        = string
  default     = "92.2.0"
}

variable "blackbox_chart_version" {
  description = "prometheus-blackbox-exporter chart version"
  type        = string
  default     = "11.20.0"
}

variable "pve_exporter_version" {
  description = "prometheus-pve-exporter image tag"
  type        = string
  default     = "3.10.1"
}
