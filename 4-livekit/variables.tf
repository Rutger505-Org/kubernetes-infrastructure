variable "base_domain" {
  description = "Base domain; LiveKit signaling is served at livekit.<base_domain>."
  type        = string
}

variable "api_key" {
  description = "LiveKit API key. Must match LIVEKIT_API_KEY used by apps."
  type        = string
  sensitive   = true
}

variable "api_secret" {
  description = "LiveKit API secret. Must match LIVEKIT_API_SECRET used by apps."
  type        = string
  sensitive   = true
}

variable "certificate_issuer" {
  description = "cert-manager ClusterIssuer for the signaling TLS certificate."
  type        = string
  default     = "letsencrypt-production"
}

variable "image" {
  description = "LiveKit server image."
  type        = string
  default     = "livekit/livekit-server:v1.8.4"
}
