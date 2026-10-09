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
    secret_suffix = "monitoring"
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

locals {
  alertmanager_secrets_dir = "/etc/alertmanager/secrets/${kubernetes_secret.alertmanager_urls.metadata[0].name}"
  watchdog_enabled         = var.watchdog_ping_url != ""
}

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
  }
}

# Alertmanager reads these URLs from files so they never end up in the rendered
# Alertmanager configuration or in the helm release values.
resource "kubernetes_secret" "alertmanager_urls" {
  metadata {
    name      = "alertmanager-urls"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }

  data = merge(
    { "discord-webhook-url" = var.discord_webhook_url },
    local.watchdog_enabled ? { "watchdog-ping-url" = var.watchdog_ping_url } : {},
  )
}

resource "kubernetes_secret" "pve_exporter" {
  metadata {
    name      = "pve-exporter-config"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }

  data = {
    "pve.yml" = yamlencode({
      default = {
        user        = var.proxmox_token_user
        token_name  = var.proxmox_token_name
        token_value = var.proxmox_token_value
        verify_ssl  = var.proxmox_verify_ssl
      }
    })
  }
}

resource "kubernetes_deployment" "pve_exporter" {
  metadata {
    name      = "pve-exporter"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
    labels = {
      app = "pve-exporter"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "pve-exporter"
      }
    }

    template {
      metadata {
        labels = {
          app = "pve-exporter"
        }
        # The exporter only reads its config file at start-up, so a rotated
        # token needs a new pod.
        annotations = {
          "checksum/config" = sha256(kubernetes_secret.pve_exporter.data["pve.yml"])
        }
      }

      spec {
        container {
          name  = "pve-exporter"
          image = "prompve/prometheus-pve-exporter:${var.pve_exporter_version}"

          port {
            name           = "http"
            container_port = 9221
          }

          volume_mount {
            name       = "config"
            mount_path = "/etc/prometheus"
            read_only  = true
          }

          resources {
            requests = {
              cpu    = "10m"
              memory = "64Mi"
            }
            limits = {
              memory = "128Mi"
            }
          }
        }

        volume {
          name = "config"
          secret {
            secret_name = kubernetes_secret.pve_exporter.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "pve_exporter" {
  metadata {
    name      = "pve-exporter"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }

  spec {
    selector = {
      app = "pve-exporter"
    }

    port {
      name        = "http"
      port        = 9221
      target_port = 9221
    }
  }
}

resource "helm_release" "blackbox_exporter" {
  name       = "blackbox-exporter"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "prometheus-blackbox-exporter"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  version    = var.blackbox_chart_version

  wait    = true
  timeout = 300

  set {
    name  = "resources.requests.memory"
    value = "32Mi"
  }

  set {
    name  = "resources.limits.memory"
    value = "64Mi"
  }
}

# Proxmox and the HTTP probes are static targets outside Kubernetes, so they
# cannot be discovered by ServiceMonitors. Both exporters use the multi-target
# pattern: the real target is passed as the `target` URL parameter.
resource "kubernetes_secret" "additional_scrape_configs" {
  metadata {
    name      = "additional-scrape-configs"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }

  data = {
    "prometheus-additional.yaml" = yamlencode([
      {
        job_name     = "proxmox"
        metrics_path = "/pve"
        params = {
          module  = ["default"]
          cluster = ["1"]
          node    = ["1"]
        }
        static_configs = [
          {
            targets = var.proxmox_targets
          }
        ]
        relabel_configs = [
          {
            source_labels = ["__address__"]
            target_label  = "__param_target"
          },
          {
            source_labels = ["__param_target"]
            target_label  = "instance"
          },
          {
            target_label = "__address__"
            replacement  = "pve-exporter.monitoring.svc.cluster.local:9221"
          }
        ]
      },
      {
        job_name     = "blackbox-http"
        metrics_path = "/probe"
        params = {
          module = ["http_2xx"]
        }
        static_configs = [
          {
            targets = var.probe_targets
          }
        ]
        relabel_configs = [
          {
            source_labels = ["__address__"]
            target_label  = "__param_target"
          },
          {
            source_labels = ["__param_target"]
            target_label  = "instance"
          },
          {
            target_label = "__address__"
            replacement  = "blackbox-exporter-prometheus-blackbox-exporter.monitoring.svc.cluster.local:9115"
          }
        ]
      }
    ])
  }
}

resource "helm_release" "kube_prometheus_stack" {
  name       = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  version    = var.kube_prometheus_stack_version

  wait    = true
  timeout = 900

  values = [yamlencode({
    # k3s runs the control plane as one embedded process and does not expose
    # these components' metrics, so their ServiceMonitors would alert forever.
    kubeControllerManager = { enabled = false }
    kubeScheduler         = { enabled = false }
    kubeEtcd              = { enabled = false }
    kubeProxy             = { enabled = false }

    # Rendered by the chart in the same release that installs the
    # PrometheusRule CRD; a separate kubernetes_manifest would fail to plan on
    # the first apply because the CRD does not exist yet.
    additionalPrometheusRulesMap = {
      homelab = {
        groups = [
          {
            name = "proxmox"
            rules = [
              {
                alert  = "ProxmoxExporterDown"
                expr   = "up{job=\"proxmox\"} == 0"
                for    = "5m"
                labels = { severity = "critical" }
                annotations = {
                  summary     = "Proxmox exporter cannot reach {{ $labels.instance }}"
                  description = "No Proxmox metrics for 5 minutes. The host is down, or the API token is invalid."
                }
              },
              # Every host in the Proxmox cluster reports the whole cluster, so
              # the rules below aggregate by id to alert once per object, and
              # keep working while one host is down.
              {
                alert  = "ProxmoxNodeDown"
                expr   = "max by (id) (pve_up{id=~\"node/.*\"}) == 0"
                for    = "5m"
                labels = { severity = "critical" }
                annotations = {
                  summary = "Proxmox node {{ $labels.id }} is offline"
                }
              },
              {
                # Only guests set to start on boot: templates and guests that
                # are deliberately kept off would otherwise alert forever.
                alert  = "ProxmoxGuestStopped"
                expr   = "max by (id) (pve_up{id=~\"(qemu|lxc)/.*\"}) == 0 and on(id) max by (id) (pve_onboot_status) == 1"
                for    = "10m"
                labels = { severity = "warning" }
                annotations = {
                  summary = "Proxmox guest {{ $labels.id }} has been stopped for 10m"
                }
              },
              {
                alert  = "ProxmoxStorageFillingUp"
                expr   = "max by (id) (pve_disk_usage_bytes{id=~\"storage/.*\"}) / max by (id) (pve_disk_size_bytes{id=~\"storage/.*\"}) > 0.85"
                for    = "15m"
                labels = { severity = "warning" }
                annotations = {
                  summary = "Proxmox storage {{ $labels.id }} is over 85% full"
                }
              }
            ]
          },
          {
            name = "blackbox"
            rules = [
              {
                alert  = "SiteDown"
                expr   = "probe_success == 0"
                for    = "5m"
                labels = { severity = "critical" }
                annotations = {
                  summary     = "{{ $labels.instance }} is not responding"
                  description = "The HTTP probe has failed for 5 minutes."
                }
              },
              {
                alert  = "SiteSlow"
                expr   = "probe_duration_seconds > 5"
                for    = "15m"
                labels = { severity = "warning" }
                annotations = {
                  summary = "{{ $labels.instance }} takes over 5s to respond"
                }
              },
              {
                # Checks the certificate actually being served, not the one
                # cert-manager believes it issued.
                alert  = "CertificateExpiringSoon"
                expr   = "(probe_ssl_earliest_cert_expiry - time()) / 86400 < 14"
                for    = "1h"
                labels = { severity = "warning" }
                annotations = {
                  summary = "TLS certificate for {{ $labels.instance }} expires in under 14 days"
                }
              }
            ]
          }
        ]
      }
    }

    prometheus = {
      prometheusSpec = {
        retention = var.prometheus_retention
        additionalScrapeConfigsSecret = {
          enabled = true
          name    = kubernetes_secret.additional_scrape_configs.metadata[0].name
          key     = "prometheus-additional.yaml"
        }

        # Pick up rules and monitors from every namespace, not only ones
        # carrying this release's label.
        ruleSelectorNilUsesHelmValues           = false
        serviceMonitorSelectorNilUsesHelmValues = false
        podMonitorSelectorNilUsesHelmValues     = false
        probeSelectorNilUsesHelmValues          = false

        resources = {
          requests = { cpu = "100m", memory = var.prometheus_memory_request }
          limits   = { memory = var.prometheus_memory_limit }
        }

        storageSpec = {
          volumeClaimTemplate = {
            spec = {
              storageClassName = var.storage_class
              accessModes      = ["ReadWriteOnce"]
              resources = {
                requests = { storage = var.prometheus_storage_size }
              }
            }
          }
        }
      }
    }

    alertmanager = {
      alertmanagerSpec = {
        secrets = [kubernetes_secret.alertmanager_urls.metadata[0].name]

        resources = {
          requests = { cpu = "10m", memory = "64Mi" }
          limits   = { memory = "128Mi" }
        }

        storage = {
          volumeClaimTemplate = {
            spec = {
              storageClassName = var.storage_class
              accessModes      = ["ReadWriteOnce"]
              resources = {
                requests = { storage = "2Gi" }
              }
            }
          }
        }
      }

      config = {
        route = {
          group_by        = ["alertname", "namespace"]
          group_wait      = "30s"
          group_interval  = "5m"
          repeat_interval = "4h"
          # Anything not matched below (info-level noise such as
          # CPUThrottlingHigh or InfoInhibitor) is dropped.
          receiver = "null"

          routes = [
            # Watchdog always fires by design and must never reach Discord.
            # Without a ping URL its receiver has no integrations and drops it.
            {
              receiver        = "watchdog"
              matchers        = ["alertname = Watchdog"]
              group_wait      = "0s"
              group_interval  = "1m"
              repeat_interval = "1m"
            },
            {
              receiver = "discord"
              matchers = ["severity =~ \"warning|critical\""]
            }
          ]
        }

        inhibit_rules = [
          {
            source_matchers = ["severity = critical"]
            target_matchers = ["severity = warning"]
            equal           = ["alertname", "namespace"]
          }
        ]

        receivers = [
          {
            name = "discord"
            discord_configs = [
              {
                webhook_url_file = "${local.alertmanager_secrets_dir}/discord-webhook-url"
                send_resolved    = true
              }
            ]
          },
          merge(
            { name = "watchdog" },
            local.watchdog_enabled ? {
              webhook_configs = [
                {
                  url_file      = "${local.alertmanager_secrets_dir}/watchdog-ping-url"
                  send_resolved = false
                }
              ]
            } : {},
          ),
          { name = "null" }
        ]
      }
    }

    grafana = {
      adminPassword = var.grafana_admin_password

      service = {
        type           = "LoadBalancer"
        loadBalancerIP = var.grafana_ip
        port           = 80
      }

      ingress = { enabled = false }

      "grafana.ini" = {
        server = {
          root_url = "http://${var.grafana_ip}/"
        }
        analytics = {
          reporting_enabled = false
          check_for_updates = false
        }
      }

      persistence = {
        enabled          = true
        size             = "2Gi"
        storageClassName = var.storage_class
      }

      resources = {
        requests = { cpu = "50m", memory = "128Mi" }
        limits   = { memory = "256Mi" }
      }

      dashboardProviders = {
        "dashboardproviders.yaml" = {
          apiVersion = 1
          providers = [
            {
              name            = "default"
              orgId           = 1
              folder          = ""
              type            = "file"
              disableDeletion = false
              editable        = true
              options         = { path = "/var/lib/grafana/dashboards/default" }
            }
          ]
        }
      }

      dashboards = {
        default = {
          proxmox = {
            gnetId     = 10347
            revision   = 6
            datasource = "Prometheus"
          }
          blackbox = {
            gnetId     = 7587
            revision   = 3
            datasource = "Prometheus"
          }
          kubernetes = {
            gnetId     = 15757
            revision   = 43
            datasource = "Prometheus"
          }
        }
      }
    }
  })]

  depends_on = [
    kubernetes_secret.additional_scrape_configs,
    kubernetes_secret.alertmanager_urls,
    kubernetes_service.pve_exporter,
    helm_release.blackbox_exporter,
  ]
}
