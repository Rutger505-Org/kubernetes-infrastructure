variable "ip_addresses" {
  description = "List of IP address ranges for MetalLB to allocate (e.g., ['192.168.1.230-192.168.1.250'])"
  type        = list(string)
  default     = ["192.168.1.230-192.168.1.250"]
}
