variable "pihole_web_ip" {
  description = "MetalLB static IP for Pi-hole web UI"
  type        = string
}

variable "pihole_dns_ip" {
  description = "MetalLB static IP for Pi-hole DNS"
  type        = string
}

variable "admin_password" {
  description = "Pi-hole admin password"
  type        = string
  sensitive   = true
}
