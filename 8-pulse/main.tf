terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
  }

  backend "kubernetes" {
    config_path   = "~/.kube/config"
    secret_suffix = "pulse"
  }
}

provider "kubernetes" {
  config_path = "~/.kube/config"
}

provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}

resource "kubernetes_namespace" "pulse" {
  metadata {
    name = "pulse"
  }
}

# Pulse hashes a plaintext PULSE_AUTH_PASS at startup. Set, it replaces the
# browser bootstrap-token setup and lets the configure Job use Basic auth.
resource "kubernetes_secret" "pulse_auth" {
  metadata {
    name      = "pulse-auth"
    namespace = kubernetes_namespace.pulse.metadata[0].name
  }

  data = {
    PULSE_AUTH_USER = var.pulse_admin_user
    PULSE_AUTH_PASS = var.pulse_admin_password
  }
}

resource "kubernetes_secret" "pulse_proxmox" {
  metadata {
    name      = "pulse-proxmox"
    namespace = kubernetes_namespace.pulse.metadata[0].name
  }

  data = {
    PVE_TOKEN_VALUE = var.proxmox_token_value
  }
}

resource "helm_release" "pulse" {
  name       = "pulse"
  namespace  = kubernetes_namespace.pulse.metadata[0].name
  repository = "https://rcourtman.github.io/Pulse"
  chart      = "pulse"
  version    = var.pulse_chart_version

  wait    = true
  timeout = 600

  values = [yamlencode({
    # The PVC is ReadWriteOnce, so a rolling update would hang on a
    # Multi-Attach error with the old pod still holding the volume.
    strategy = { type = "Recreate" }

    # LAN only: Caddy on the reverse-proxy VM serves it as
    # https://${var.pulse_hostname}. Local keeps Caddy's address as the client
    # IP, which Pulse needs to trust its forwarded HTTPS headers.
    service = {
      type                  = "LoadBalancer"
      loadBalancerIP        = var.pulse_load_balancer_ip
      externalTrafficPolicy = "Local"
    }

    # Holds the encrypted Proxmox credentials and history. local-path on the
    # node's root disk, not backed up.
    persistence = {
      enabled = true
      size    = "2Gi"
    }

    server = {
      # Restart on a password change: env from a Secret is only read at startup.
      podAnnotations = {
        "checksum/auth" = sha256(jsonencode(kubernetes_secret.pulse_auth.data))
      }
      # Not extraEnvFrom: chart 6.5.0 renders its items without the list dash,
      # which the API server rejects. secretEnv maps each key with secretKeyRef.
      secretEnv = {
        create = false
        name   = kubernetes_secret.pulse_auth.metadata[0].name
        keys   = keys(kubernetes_secret.pulse_auth.data)
      }
      extraEnv = [
        { name = "PULSE_PUBLIC_URL", value = "https://${var.pulse_hostname}" },
        # local-path ignores fsGroup, so the volume root is root-owned and Pulse
        # refuses it for its metrics history. It creates this subdirectory
        # itself, owned by its own user.
        { name = "PULSE_DATA_DIR", value = "/data/pulse" },
        { name = "PULSE_TRUSTED_PROXY_CIDRS", value = var.trusted_proxy_cidrs },
      ]
      resources = {
        requests = { cpu = "50m", memory = "128Mi" }
        limits   = { memory = "512Mi" }
      }
    }
  })]
}

locals {
  configure_script = file("${path.module}/configure-proxmox.py")

  # Rerun the Job whenever Pulse is installed or upgraded (a new PVC starts
  # empty), the script changes, or the connection or a credential changes.
  configure_hash = substr(sha256(jsonencode({
    revision = helm_release.pulse.metadata[0].revision
    script   = local.configure_script
    host     = var.proxmox_host
    name     = var.proxmox_connection_name
    token_id = var.proxmox_token_id
    secrets  = [kubernetes_secret.pulse_auth.data, kubernetes_secret.pulse_proxmox.data]
  })), 0, 10)
}

resource "kubernetes_config_map" "configure_proxmox" {
  metadata {
    name      = "pulse-configure-proxmox"
    namespace = kubernetes_namespace.pulse.metadata[0].name
  }

  data = {
    "configure-proxmox.py" = local.configure_script
  }
}

# Pulse keeps its Proxmox connections in its own encrypted store, with no
# config file or env var for them, so this Job sets the connection through its
# API. The name changes with configure_hash, which replaces the Job.
resource "kubernetes_job_v1" "configure_proxmox" {
  metadata {
    name      = "pulse-configure-proxmox-${local.configure_hash}"
    namespace = kubernetes_namespace.pulse.metadata[0].name
  }

  spec {
    backoff_limit = 3

    template {
      metadata {}

      spec {
        restart_policy = "Never"

        container {
          name    = "configure"
          image   = "python:${var.python_version}-alpine"
          command = ["python", "/script/configure-proxmox.py"]

          env {
            name  = "PULSE_URL"
            value = "http://pulse.${kubernetes_namespace.pulse.metadata[0].name}.svc.cluster.local:7655"
          }
          env {
            name  = "PVE_NAME"
            value = var.proxmox_connection_name
          }
          env {
            name  = "PVE_HOST"
            value = var.proxmox_host
          }
          env {
            name  = "PVE_TOKEN_ID"
            value = var.proxmox_token_id
          }
          env {
            name  = "PVE_VERIFY_SSL"
            value = tostring(var.proxmox_verify_ssl)
          }

          env_from {
            secret_ref {
              name = kubernetes_secret.pulse_auth.metadata[0].name
            }
          }
          env_from {
            secret_ref {
              name = kubernetes_secret.pulse_proxmox.metadata[0].name
            }
          }

          volume_mount {
            name       = "script"
            mount_path = "/script"
            read_only  = true
          }

          resources {
            requests = { cpu = "10m", memory = "32Mi" }
            limits   = { memory = "64Mi" }
          }
        }

        volume {
          name = "script"
          config_map {
            name = kubernetes_config_map.configure_proxmox.metadata[0].name
          }
        }
      }
    }
  }

  # No ttl_seconds_after_finished: a cleaned-up Job would be recreated, and
  # rerun, on every apply.
  wait_for_completion = true

  timeouts {
    create = "10m"
  }
}
