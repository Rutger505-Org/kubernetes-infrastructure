provider "kubernetes" {
  config_path = "~/.kube/config"
}

provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}

resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true
  version          = "v1.17.2"

  set {
    name  = "installCRDs"
    value = "true"
  }
}

# Create Let's Encrypt issuers
resource "kubernetes_manifest" "letsencrypt_issuer" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt-prod"
    }
    spec = {
      acme = {
        server = "https://acme-v02.api.letsencrypt.org/directory"
        email  = "your-email@example.com"
        privateKeySecretRef = {
          name = "letsencrypt-prod"
        }
        solvers = [
          {
            http01 = {
              ingress = {
                class = "gce"
              }
            }
          }
        ]
      }
    }
  }

  depends_on = [helm_release.cert_manager]
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

# Create Let's Encrypt issuers using for_each
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

  depends_on = [helm_release.cert_manager]
}