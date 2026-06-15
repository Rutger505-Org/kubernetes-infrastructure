variable "cluster_endpoint" {
  description = <<-EOT
    Kubernetes API server URL embedded into the generated read-only kubeconfig
    (e.g. https://1.2.3.4:6443). The CA cert and token are pulled from the
    service-account token secret automatically; only the endpoint has to be
    supplied. Leave empty if you only want the secret created and will fill in
    the server yourself.
  EOT
  type        = string
  default     = ""
}
