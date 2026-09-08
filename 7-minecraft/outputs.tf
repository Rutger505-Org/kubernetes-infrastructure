output "router_ip" {
  description = "MetalLB IP serving Minecraft traffic on 25565. Forward the router's 25565 here."
  value       = var.router_ip
}

output "hostname" {
  description = "Hostname players connect to; mc-router matches on it."
  value       = var.hostname
}

output "server_type" {
  description = "Active server type (VANILLA until a real CurseForge key is in place)."
  value       = var.server_type
}
