output "http3_service_name" {
  description = "Name of the Service that exposes Traefik's QUIC listener"
  value       = kubernetes_service.traefik_http3.metadata[0].name
}

output "http3_endpoint" {
  description = "Address and UDP port serving HTTP/3"
  value       = "${var.traefik_ip}:${var.advertised_port}/udp"
}
