terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
  }

  backend "kubernetes" {
    config_path   = "~/.kube/config"
    secret_suffix = "home-assistant"
  }
}

provider "kubernetes" {
  config_path = "~/.kube/config"
}

# Home Assistant plus a Mosquitto MQTT broker, LAN only. The motorized-blinds
# drivers (built with the `mqtt` feature) connect to Mosquitto and announce
# themselves through MQTT discovery, so Home Assistant picks them up as covers.

locals {
  namespace = kubernetes_namespace.home_assistant.metadata[0].name
}

resource "kubernetes_namespace" "home_assistant" {
  metadata {
    name = "home-assistant"
  }
}

# ---------------------------------------------------------------- Mosquitto

resource "kubernetes_config_map" "mosquitto" {
  metadata {
    name      = "mosquitto-config"
    namespace = local.namespace
  }

  data = {
    "mosquitto.conf" = <<-EOT
      listener 1883
      allow_anonymous false
      password_file /mosquitto/auth/passwd
      # Discovery configs and blind states are retained messages; keep them
      # across restarts so Home Assistant sees the blinds straight away.
      persistence true
      persistence_location /mosquitto/data/
      log_dest stdout
    EOT
  }
}

resource "kubernetes_secret" "mosquitto" {
  metadata {
    name      = "mosquitto-credentials"
    namespace = local.namespace
  }

  data = {
    username = var.mqtt_username
    password = var.mqtt_password
  }
}

resource "kubernetes_persistent_volume_claim" "mosquitto" {
  metadata {
    name      = "mosquitto-data"
    namespace = local.namespace
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = var.storage_class
    resources {
      requests = { storage = "100Mi" }
    }
  }

  wait_until_bound = false
}

resource "kubernetes_deployment" "mosquitto" {
  metadata {
    name      = "mosquitto"
    namespace = local.namespace
    labels    = { app = "mosquitto" }
  }

  spec {
    replicas = 1

    # RWO volume: the old pod has to let go before the new one starts.
    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = { app = "mosquitto" }
    }

    template {
      metadata {
        labels = { app = "mosquitto" }
        annotations = {
          "checksum/config"      = sha256(kubernetes_config_map.mosquitto.data["mosquitto.conf"])
          "checksum/credentials" = sha256("${var.mqtt_username}:${var.mqtt_password}")
        }
      }

      spec {
        # Hashes the password into a password file mosquitto can read, and hands
        # the data directory to the mosquitto user (uid 1883).
        init_container {
          name  = "passwd"
          image = "eclipse-mosquitto:${var.mosquitto_version}"
          command = ["sh", "-c", <<-EOT
            set -e
            mosquitto_passwd -b -c /mosquitto/auth/passwd "$MQTT_USERNAME" "$MQTT_PASSWORD"
            chown 1883:1883 /mosquitto/auth/passwd /mosquitto/data
            chmod 0600 /mosquitto/auth/passwd
          EOT
          ]

          env {
            name = "MQTT_USERNAME"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.mosquitto.metadata[0].name
                key  = "username"
              }
            }
          }

          env {
            name = "MQTT_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.mosquitto.metadata[0].name
                key  = "password"
              }
            }
          }

          volume_mount {
            name       = "auth"
            mount_path = "/mosquitto/auth"
          }

          volume_mount {
            name       = "data"
            mount_path = "/mosquitto/data"
          }
        }

        container {
          name  = "mosquitto"
          image = "eclipse-mosquitto:${var.mosquitto_version}"

          port {
            name           = "mqtt"
            container_port = 1883
          }

          volume_mount {
            name       = "config"
            mount_path = "/mosquitto/config"
            read_only  = true
          }

          volume_mount {
            name       = "auth"
            mount_path = "/mosquitto/auth"
          }

          volume_mount {
            name       = "data"
            mount_path = "/mosquitto/data"
          }

          readiness_probe {
            tcp_socket {
              port = 1883
            }
            period_seconds = 10
          }

          resources {
            requests = {
              cpu    = "10m"
              memory = "16Mi"
            }
            limits = {
              memory = "64Mi"
            }
          }
        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.mosquitto.metadata[0].name
          }
        }

        volume {
          name = "auth"
          empty_dir {}
        }

        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.mosquitto.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "mosquitto" {
  metadata {
    name      = "mosquitto"
    namespace = local.namespace
  }

  spec {
    type             = "LoadBalancer"
    load_balancer_ip = var.mqtt_ip
    selector         = { app = "mosquitto" }

    port {
      name        = "mqtt"
      port        = 1883
      target_port = 1883
      protocol    = "TCP"
    }
  }
}

# ----------------------------------------------------------- Home Assistant

resource "kubernetes_persistent_volume_claim" "home_assistant" {
  metadata {
    name      = "home-assistant-config"
    namespace = local.namespace
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = var.storage_class
    resources {
      requests = { storage = var.home_assistant_storage_size }
    }
  }

  wait_until_bound = false
}

resource "kubernetes_deployment" "home_assistant" {
  metadata {
    name      = "home-assistant"
    namespace = local.namespace
    labels    = { app = "home-assistant" }
  }

  spec {
    replicas = 1

    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = { app = "home-assistant" }
    }

    template {
      metadata {
        labels = { app = "home-assistant" }
      }

      spec {
        container {
          name  = "home-assistant"
          image = "ghcr.io/home-assistant/home-assistant:${var.home_assistant_version}"

          env {
            name  = "TZ"
            value = var.timezone
          }

          port {
            name           = "http"
            container_port = 8123
          }

          volume_mount {
            name       = "config"
            mount_path = "/config"
          }

          readiness_probe {
            tcp_socket {
              port = 8123
            }
            initial_delay_seconds = 15
            period_seconds        = 10
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "384Mi"
            }
            limits = {
              memory = "1Gi"
            }
          }
        }

        volume {
          name = "config"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.home_assistant.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "home_assistant" {
  metadata {
    name      = "home-assistant"
    namespace = local.namespace
  }

  spec {
    type             = "LoadBalancer"
    load_balancer_ip = var.home_assistant_ip
    selector         = { app = "home-assistant" }

    port {
      name        = "http"
      port        = 8123
      target_port = 8123
      protocol    = "TCP"
    }
  }
}
