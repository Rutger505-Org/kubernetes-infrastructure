output "grafana_url" {
  description = "Grafana, reachable on the LAN and over Tailscale only"
  value       = "http://${var.grafana_ip}"
}

output "monitoring_namespace" {
  description = "Namespace holding Prometheus, Alertmanager, Grafana and the exporters"
  value       = kubernetes_namespace.monitoring.metadata[0].name
}

output "probe_targets" {
  description = "URLs currently probed by blackbox-exporter"
  value       = var.probe_targets
}
