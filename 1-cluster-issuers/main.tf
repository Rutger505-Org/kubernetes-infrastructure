provider "kubernetes" {
  config_path = "~/.kube/config"
}


locals {
  issuers = {
    "letsencrypt-staging" = {
      server = "https://acme-staging-v02.api.letsencrypt.org/directory"
    },
    "letsencrypt-production" = {
      server = "https://acme-v02.api.letsencrypt.org/directory"
    }
  }
}

resource "kubernetes_manifest" "letsencrypt_issuers" {
  for_each = local.issuers

  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = each.key
    }
    spec = {
      acme = {
        server = each.value.server
        email  = var.cert_email
        privateKeySecretRef = {
          name = each.key
        }
        solvers = [
          {
            http01 = {
              ingress = {
                class = "traefik"
              }
            }
          }
        ]
      }
    }
  }
}
