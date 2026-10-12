output "home_assistant_url" {
  description = "Home Assistant web UI on the LAN"
  value       = "http://${var.home_assistant_ip}:8123"
}

output "mqtt_broker" {
  description = "Mosquitto address for Home Assistant and the blind drivers (MQTT_BROKER)"
  value       = "${var.mqtt_ip}:1883"
}

output "home_assistant_namespace" {
  description = "Namespace holding Home Assistant and Mosquitto"
  value       = kubernetes_namespace.home_assistant.metadata[0].name
}
