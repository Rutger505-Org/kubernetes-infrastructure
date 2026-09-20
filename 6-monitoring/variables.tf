variable "discord_webhook_url" {
  description = "Discord channel webhook URL that Alertmanager posts alerts to"
  type        = string
  sensitive   = true
}

variable "healthchecks_ping_url" {
  description = "External healthchecks.io ping URL for the Watchdog dead man's switch (period 5m, grace 5m). When the cluster dies the pings stop and healthchecks.io notifies independently."
  type        = string
  sensitive   = true
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
  description = "Proxmox API token user, e.g. 'prometheus@pve'"
  type        = string
  default     = ""
}

variable "proxmox_token_name" {
  description = "Proxmox API token name (the part after '!')"
  type        = string
  default     = ""
}

variable "proxmox_token_value" {
  description = "Proxmox API token secret. Create it with the read-only PVEAuditor role; it is never used to change anything."
  type        = string
  sensitive   = true
  default     = ""
}

variable "proxmox_verify_ssl" {
  description = "Verify the Proxmox API certificate. False by default because Proxmox ships a self-signed certificate."
  type        = bool
  default     = false
}

variable "proxmox_targets" {
  description = "Proxmox API endpoints to scrape, as host:port (8006 is the API port), e.g. ['192.168.178.10:8006']"
  type        = list(string)
  default     = []
}

variable "probe_targets" {
  description = "URLs blackbox-exporter probes over HTTP"
  type        = list(string)
  default     = []
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
  description = "StorageClass backing the monitoring PVCs (K3s default is 'local-path')"
  type        = string
  default     = "local-path"
}

variable "kube_prometheus_stack_version" {
  description = "kube-prometheus-stack chart version"
  type        = string
  default     = "91.2.0"
}

variable "blackbox_chart_version" {
  description = "prometheus-blackbox-exporter chart version"
  type        = string
  default     = "4.3.0"
}

variable "pve_exporter_version" {
  description = "prometheus-pve-exporter image tag"
  type        = string
  default     = "3.5.5"
}
