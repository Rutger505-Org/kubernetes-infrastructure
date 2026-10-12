variable "mqtt_ip" {
  description = "MetalLB address for the Mosquitto broker (port 1883), from the 192.168.178.230-250 pool"
  type        = string
}

variable "home_assistant_ip" {
  description = "MetalLB address for the Home Assistant web UI (port 8123), from the 192.168.178.230-250 pool"
  type        = string
}

variable "mqtt_username" {
  description = "MQTT user shared by Home Assistant and the blind drivers"
  type        = string
  default     = "homeassistant"
}

variable "mqtt_password" {
  description = "Password of the MQTT user"
  type        = string
  sensitive   = true
}

variable "mosquitto_version" {
  description = "eclipse-mosquitto image tag"
  type        = string
  default     = "2.0.22"
}

variable "home_assistant_version" {
  description = "ghcr.io/home-assistant/home-assistant image tag"
  type        = string
  default     = "2026.10.1"
}

variable "home_assistant_storage_size" {
  description = "Size of the Home Assistant /config volume (config, database, logs)"
  type        = string
  default     = "2Gi"
}

variable "storage_class" {
  description = "StorageClass backing the PVCs"
  type        = string
  default     = "local-path"
}

variable "timezone" {
  description = "Timezone Home Assistant runs in"
  type        = string
  default     = "Europe/Amsterdam"
}
