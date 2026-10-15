variable "pulse_chart_version" {
  description = "Pulse Helm chart version (its appVersion is the Pulse image tag)"
  type        = string
  default     = "6.5.0"
}

variable "pulse_load_balancer_ip" {
  description = "MetalLB address of the Pulse Service, Caddy's upstream. Must not be port-forwarded by the router."
  type        = string
  default     = "192.168.178.232"
}

variable "pulse_hostname" {
  description = "Hostname Caddy serves Pulse on"
  type        = string
  default     = "pulse.homelab.rutgerpronk.com"
}

variable "trusted_proxy_cidrs" {
  description = "Proxies whose forwarded headers Pulse trusts: the Caddy reverse-proxy VM"
  type        = string
  default     = "192.168.178.207/32"
}

variable "pulse_admin_user" {
  description = "Pulse admin username"
  type        = string
  default     = "admin"
}

variable "pulse_admin_password" {
  description = "Pulse admin password, plaintext (Pulse hashes it at startup)"
  type        = string
  sensitive   = true
}

variable "proxmox_connection_name" {
  description = "Name of the Proxmox connection in Pulse; the configure Job finds it by this name"
  type        = string
  default     = "homelab"
}

variable "proxmox_host" {
  description = "Proxmox API endpoint. Pulse detects the cluster from it and polls every node."
  type        = string
  default     = "https://192.168.178.200:8006"
}

variable "proxmox_token_id" {
  description = "Proxmox API token ID (user@realm!name). Shared with 7-monitoring's pve-exporter; its privileges are managed in homelab-infrastructure."
  type        = string
  default     = "prometheus@pve!monitoring"
}

variable "proxmox_token_value" {
  description = "Secret of proxmox_token_id"
  type        = string
  sensitive   = true
}

variable "proxmox_verify_ssl" {
  description = "Verify the Proxmox API certificate. False by default because Proxmox ships a self-signed certificate."
  type        = bool
  default     = false
}

variable "python_version" {
  description = "python:<version>-alpine image tag for the configure Job"
  type        = string
  default     = "3.13"
}
