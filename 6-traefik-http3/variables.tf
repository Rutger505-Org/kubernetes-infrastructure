variable "traefik_ip" {
  description = "Static IP address of the Traefik LoadBalancer service (must match the MetalLB config)"
  type        = string
}

variable "advertised_port" {
  description = "Port advertised in the Alt-Svc header, i.e. the public UDP port clients reach"
  type        = number
  default     = 443
}
