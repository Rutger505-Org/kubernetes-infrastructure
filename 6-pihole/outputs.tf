output "dns_ip" {
  description = "LoadBalancer IP serving DNS on port 53 — set as the router's primary DNS."
  value       = var.dns_ip
}

output "web_ip" {
  description = "LoadBalancer IP for the admin web UI (http://<web_ip>/admin)."
  value       = var.web_ip
}
