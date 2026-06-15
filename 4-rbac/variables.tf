variable "cluster_endpoint" {
  description = <<-EOT
    Kubernetes API server URL embedded into the generated read-only kubeconfig.
    The CA cert and token are pulled from the service-account token secret
    automatically; only the endpoint has to be supplied. Defaults to the
    Tailscale-exposed API server that both laptops and CI connect to.
  EOT
  type        = string
  default     = "https://192.168.178.201:6443"
}
