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
