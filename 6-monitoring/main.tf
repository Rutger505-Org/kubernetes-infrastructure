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

# Monitoring + alerting for both the k3s cluster and the Proxmox datacenter.
#
# Layers:
#   - kube-state-metrics / node-exporter (bundled in kube-prometheus-stack)
#     cover "is the cluster healthy": crashlooping pods, unavailable replicas,
#     node pressure, disk filling up. No application changes required.
#   - blackbox-exporter HTTP-probes the public sites, which catches the case a
#     pod is Running while the site returns 500 or the certificate expired.
#   - pve-exporter pulls Proxmox node/VM/LXC/storage metrics over the API with a
#     read-only PVEAuditor token. Nothing in this repo ever touches the
#     hypervisor itself.
#
# Alerts go to Discord. Grafana is LAN/Tailscale-only: it gets a MetalLB address
# and deliberately no Traefik IngressRoute and no public certificate.
#
# Caveat, by design: Prometheus runs inside the cluster it watches, so it cannot
# alert on its own cluster dying. The always-firing Watchdog alert is routed to
# an external healthchecks.io check every minute; when k3s goes down the pings
# stop and healthchecks.io notifies independently of any of this.

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
  }
}

# --- Secrets -----------------------------------------------------------------

# Alertmanager reads the Discord webhook and the healthchecks ping URL from
# files rather than inline config, so neither ends up in the rendered
# Alertmanager configuration or in helm release values.
resource "kubernetes_secret" "alertmanager_urls" {
  metadata {
    name      = "alertmanager-urls"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }

  data = {
    "discord-webhook-url" = var.discord_webhook_url
    "watchdog-ping-url"   = var.healthchecks_ping_url
  }
}

# pve-exporter's own config file: which Proxmox endpoint to talk to and with
# which API token. Read-only (PVEAuditor) by convention; see the module README.
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

# --- Proxmox exporter --------------------------------------------------------

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
        # Recreate the pod when the token changes, otherwise the running
        # process keeps using the old credentials from its mounted file.
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

# --- Blackbox exporter -------------------------------------------------------

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

# --- Scrape configuration for the two non-Kubernetes targets -----------------

# Kubernetes targets are discovered by the operator's ServiceMonitors. Proxmox
# and the HTTP probes are static, so they live in the additional scrape config
# secret the operator merges in verbatim.
resource "kubernetes_secret" "additional_scrape_configs" {
  metadata {
    name      = "additional-scrape-configs"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }

  data = {
    "prometheus-additional.yaml" = yamlencode([
      # pve-exporter uses the multi-target pattern: the Proxmox host to query is
      # passed as the `target` parameter, so one exporter serves every node.
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
      # Same pattern for blackbox: probe each URL through the exporter.
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

# --- kube-prometheus-stack ---------------------------------------------------

resource "helm_release" "kube_prometheus_stack" {
  name       = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  version    = var.kube_prometheus_stack_version

  wait    = true
  timeout = 900

  values = [yamlencode({
    # k3s runs the control plane as a single embedded process and does not
    # expose scheduler/controller-manager/etcd metrics on the usual ports, so
    # those bundled ServiceMonitors would alert on targets that can never exist.
    kubeControllerManager = { enabled = false }
    kubeScheduler         = { enabled = false }
    kubeEtcd              = { enabled = false }
    kubeProxy             = { enabled = false }

    prometheus = {
      prometheusSpec = {
        retention = var.prometheus_retention
        additionalScrapeConfigsSecret = {
          enabled = true
          name    = kubernetes_secret.additional_scrape_configs.metadata[0].name
          key     = "prometheus-additional.yaml"
        }

        # Pick up PrometheusRules and ServiceMonitors from every namespace,
        # not only ones carrying the release label.
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
        # Mounted at /etc/alertmanager/secrets/<secret name>/ so the receivers
        # below can read the webhook URLs from disk.
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
          # Group related alerts into one Discord message instead of a burst.
          group_by       = ["alertname", "namespace"]
          group_wait     = "30s"
          group_interval = "5m"
          # Re-notify every 4 hours while something is still broken; often
          # enough to not forget, rare enough to not become noise you mute.
          repeat_interval = "4h"
          receiver        = "discord"

          routes = [
            # The Watchdog alert always fires by design. It must never reach
            # Discord; it goes to healthchecks.io as the dead man's switch.
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
          # A critical alert already says enough; drop the warning duplicate.
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
                webhook_url_file = "/etc/alertmanager/secrets/${kubernetes_secret.alertmanager_urls.metadata[0].name}/discord-webhook-url"
                send_resolved    = true
              }
            ]
          },
          {
            name = "watchdog"
            webhook_configs = [
              {
                url_file      = "/etc/alertmanager/secrets/${kubernetes_secret.alertmanager_urls.metadata[0].name}/watchdog-ping-url"
                send_resolved = false
              }
            ]
          }
        ]
      }
    }

    grafana = {
      adminPassword = var.grafana_admin_password

      # Tailscale/LAN only: a MetalLB address on the home network, reachable
      # over the tailnet through the subnet router. No IngressRoute, no
      # public certificate, nothing published to the internet.
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

      # Community dashboards, pulled at start-up by the sidecar.
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
          # Proxmox cluster overview (pve-exporter).
          proxmox = {
            gnetId     = 10347
            revision   = 6
            datasource = "Prometheus"
          }
          # Blackbox probe overview: uptime, latency, TLS expiry.
          blackbox = {
            gnetId     = 7587
            revision   = 3
            datasource = "Prometheus"
          }
          # Cluster capacity and per-namespace usage.
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

# --- Alert rules for the targets the bundled rules know nothing about --------

resource "kubernetes_manifest" "custom_rules" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PrometheusRule"
    metadata = {
      name      = "homelab-rules"
      namespace = kubernetes_namespace.monitoring.metadata[0].name
    }
    spec = {
      groups = [
        {
          name = "proxmox"
          rules = [
            {
              # pve-exporter cannot reach the API, or the node is gone.
              alert  = "ProxmoxExporterDown"
              expr   = "up{job=\"proxmox\"} == 0"
              for    = "5m"
              labels = { severity = "critical" }
              annotations = {
                summary     = "Proxmox exporter cannot reach {{ $labels.instance }}"
                description = "No Proxmox metrics for 5 minutes. The node is down, or the API token is invalid."
              }
            },
            {
              alert  = "ProxmoxNodeDown"
              expr   = "pve_node_info and on(id) pve_up == 0"
              for    = "5m"
              labels = { severity = "critical" }
              annotations = {
                summary = "Proxmox node {{ $labels.id }} is offline"
              }
            },
            {
              # A guest that stopped without anyone stopping it on purpose is
              # exactly the failure this whole module exists to catch.
              alert  = "ProxmoxGuestStopped"
              expr   = "pve_up{id=~\"(qemu|lxc)/.*\"} == 0"
              for    = "10m"
              labels = { severity = "warning" }
              annotations = {
                summary = "Proxmox guest {{ $labels.id }} has been stopped for 10m"
              }
            },
            {
              alert  = "ProxmoxStorageFillingUp"
              expr   = "pve_disk_usage_bytes{id=~\"storage/.*\"} / pve_disk_size_bytes{id=~\"storage/.*\"} > 0.85"
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
                description = "The HTTP probe has failed for 5 minutes. The pod may be Running while the site is broken."
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
              # Long before Let's Encrypt's own expiry mail, and it checks the
              # certificate actually being served rather than the one issued.
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

  depends_on = [helm_release.kube_prometheus_stack]
}
