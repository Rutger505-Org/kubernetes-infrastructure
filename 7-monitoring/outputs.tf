output "grafana_url" {
  description = "Public Grafana URL"
  value       = "https://${var.grafana_hostname}"
}

output "monitoring_namespace" {
  description = "Namespace holding Prometheus, Alertmanager, Grafana and the exporters"
  value       = kubernetes_namespace.monitoring.metadata[0].name
}

output "probe_targets" {
  description = "URLs currently probed by blackbox-exporter"
  value       = var.probe_targets
}
