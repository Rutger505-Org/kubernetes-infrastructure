variable "ip_addresses" {
  description = "List of IP address ranges for MetalLB to allocate (e.g., ['192.168.1.230-192.168.1.250'])"
  type        = list(string)
}

variable "traefik_ip" {
  description = "Static IP address to assign to the Traefik LoadBalancer service"
  type        = string
}
