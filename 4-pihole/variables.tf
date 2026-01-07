variable "pihole_ip" {
  description = "MetalLB static IP for Pi-hole services"
  type        = string
}

variable "admin_password" {
  description = "Pi-hole admin password"
  type        = string
  sensitive   = true
}
