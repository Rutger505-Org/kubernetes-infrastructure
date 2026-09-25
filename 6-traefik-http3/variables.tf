variable "traefik_ip" {
  description = "Static IP address shared by the traefik and traefik-http3 LoadBalancer services (must come from the MetalLB pool in 3-metallb-config)"
  type        = string
}

variable "advertised_port" {
  description = "Public UDP port for QUIC, also the port advertised in the Alt-Svc header"
  type        = number
  default     = 443
}

variable "websecure_container_port" {
  description = "Numeric container port of Traefik's websecure entrypoint, used as the targetPort of the UDP service"
  type        = number
  default     = 8443
}
