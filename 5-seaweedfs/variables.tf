variable "cdn_hostname" {
  description = "Public hostname for the S3 gateway / CDN (e.g. 'cdn.rutgerpronk.com')"
  type        = string

  validation {
    condition     = length(var.cdn_hostname) > 0
    error_message = "cdn_hostname must be set (CI variable CDN_HOSTNAME)."
  }
}

variable "bucket_names" {
  description = "Buckets to create, one per use case; objects are anonymously readable"
  type        = list(string)
  default     = ["clips", "artifacts"]
}

variable "storage_size" {
  description = "Size of the SeaweedFS persistent volume (e.g. '30Gi')"
  type        = string
  default     = "30Gi"
}

variable "storage_class" {
  description = "StorageClass backing the SeaweedFS PVC (K3s default is 'local-path')"
  type        = string
  default     = "local-path"
}

variable "memory_request" {
  description = "SeaweedFS pod memory request"
  type        = string
  default     = "128Mi"
}

variable "memory_limit" {
  description = "SeaweedFS pod memory limit"
  type        = string
  default     = "512Mi"
}

variable "certificate_issuer" {
  description = "cert-manager ClusterIssuer to use for TLS"
  type        = string
  default     = "letsencrypt-production"
}
