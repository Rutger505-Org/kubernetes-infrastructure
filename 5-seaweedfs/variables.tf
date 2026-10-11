variable "cdn_hostname" {
  description = "Public hostname for the S3 gateway / CDN (e.g. 'cdn.rutgerpronk.com')"
  type        = string

  validation {
    condition     = length(var.cdn_hostname) > 0
    error_message = "cdn_hostname must be set (CI variable CDN_HOSTNAME)."
  }
}

variable "seaweedfs_ip" {
  description = "LAN address of the SeaweedFS VM (e.g. '192.168.178.214')"
  type        = string

  validation {
    condition     = can(cidrhost("${var.seaweedfs_ip}/32", 0))
    error_message = "seaweedfs_ip must be an IPv4 address (CI variable SEAWEEDFS_IP)."
  }
}

variable "seaweedfs_s3_port" {
  description = "S3 gateway port on the SeaweedFS VM"
  type        = number
  default     = 8333
}

variable "certificate_issuer" {
  description = "cert-manager ClusterIssuer to use for TLS"
  type        = string
  default     = "letsencrypt-production"
}

variable "bucket_names" {
  description = "Buckets on the VM, only used for the cdn_urls output; they are created by the seaweedfs Ansible role"
  type        = list(string)
  default     = ["clips", "artifacts"]
}
