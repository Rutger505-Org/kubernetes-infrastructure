variable "dns_ip" {
  description = "Fixed MetalLB LoadBalancer IP for the DNS service (port 53). Must be in the pool from 3-metallb-config. Set the router's primary DNS to this."
  type        = string
}

variable "web_ip" {
  description = "Fixed MetalLB LoadBalancer IP for the admin web UI (LAN-only, no public hostname)."
  type        = string
}

variable "web_password" {
  description = "Pi-hole admin web password."
  type        = string
  sensitive   = true
}

variable "upstream_dns_1" {
  description = "Primary upstream DNS resolver."
  type        = string
  default     = "1.1.1.1"
}

variable "upstream_dns_2" {
  description = "Secondary upstream DNS resolver."
  type        = string
  default     = "1.0.0.1"
}

variable "storage_size" {
  description = "Size of the local-path PVC for Pi-hole config + gravity DB."
  type        = string
  default     = "2Gi"
}

variable "storage_class" {
  description = "StorageClass for the Pi-hole PVC."
  type        = string
  default     = "local-path"
}
