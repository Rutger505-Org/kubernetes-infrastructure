variable "root_user" {
  description = "MinIO root (admin) username"
  type        = string
}

variable "root_password" {
  description = "MinIO root (admin) password"
  type        = string
  sensitive   = true
}

variable "bucket_name" {
  description = "Name of the public CDN bucket to provision (anonymous read-only)"
  type        = string
  default     = "cdn"
}

variable "storage_size" {
  description = "Size of the MinIO persistent volume (e.g. '240Gi')"
  type        = string
  default     = "240Gi"
}

variable "storage_class" {
  description = "StorageClass backing MinIO's PVC (K3s default is 'local-path')"
  type        = string
  default     = "local-path"
}

variable "cdn_hostname" {
  description = "Public hostname for the S3 API / CDN (e.g. 'cdn.rutgerpronk.com')"
  type        = string
}

variable "console_hostname" {
  description = "Hostname for the MinIO admin console (e.g. 'minio.rutgerpronk.com')"
  type        = string
}

variable "certificate_issuer" {
  description = "cert-manager ClusterIssuer to use for TLS"
  type        = string
  default     = "letsencrypt-production"
}
