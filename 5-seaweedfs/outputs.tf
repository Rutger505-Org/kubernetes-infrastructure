output "cdn_urls" {
  description = "Base URL per public bucket"
  value       = { for name in var.bucket_names : name => "https://${var.cdn_hostname}/${name}" }
}

output "s3_endpoint" {
  description = "S3 endpoint for uploads (admin credentials are the SEAWEEDFS_ADMIN_* secrets in homelab-infrastructure)"
  value       = "https://${var.cdn_hostname}"
}
