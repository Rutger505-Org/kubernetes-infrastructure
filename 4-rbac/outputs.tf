output "kubeconfig" {
  sensitive = true
  value = yamlencode({
    apiVersion        = "v1"
    kind              = "Config"
    "current-context" = "readonly"
    clusters = [{
      name = "cluster"
      cluster = {
        server                        = var.cluster_endpoint
        "certificate-authority-data" = base64encode(kubernetes_secret.readonly_token.data["ca.crt"])
      }
    }]
    contexts = [{
      name = "readonly"
      context = {
        cluster   = "cluster"
        user      = "readonly"
        namespace = kubernetes_namespace.readonly.metadata[0].name
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

output "token" {
  sensitive = true
  value     = kubernetes_secret.readonly_token.data["token"]
}
