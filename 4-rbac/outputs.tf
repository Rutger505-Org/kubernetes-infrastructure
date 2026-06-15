# Ready-to-use, non-expiring kubeconfig scoped to the read-only debug rights.
# Extract it with:
#
#   tofu output -raw kubeconfig > readonly.kubeconfig
#   KUBECONFIG=readonly.kubeconfig kubectl get pods -A
#
# Marked sensitive so the token never lands in plan/apply logs.
output "kubeconfig" {
  description = "Permanent read-only kubeconfig (token + CA baked in). Extract with: tofu output -raw kubeconfig > readonly.kubeconfig"
  sensitive   = true
  value = yamlencode({
    apiVersion        = "v1"
    kind              = "Config"
    "current-context" = "readonly"
    clusters = [{
      name = "cluster"
      cluster = {
        server                     = var.cluster_endpoint
        "certificate-authority-data" = base64encode(kubernetes_secret.readonly_token.data["ca.crt"])
      }
    }]
    contexts = [{
      name = "readonly"
      context = {
        cluster   = "cluster"
        user      = "readonly"
        namespace = "readonly"
      }
    }]
    users = [{
      name = "readonly"
      user = {
        token = kubernetes_secret.readonly_token.data["token"]
      }
    }]
  })
}

# The raw token, in case you want to build the kubeconfig by hand or feed it to
# another tool. Sensitive for the same reason as above.
output "token" {
  description = "Long-lived read-only service account token."
  sensitive   = true
  value       = kubernetes_secret.readonly_token.data["token"]
}
