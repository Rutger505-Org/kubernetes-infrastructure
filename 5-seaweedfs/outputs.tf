output "cdn_urls" {
  description = "Base URL per public bucket"
  value       = { for name in var.bucket_names : name => "https://${var.cdn_hostname}/${name}" }
}

output "s3_endpoint" {
  description = "S3 endpoint for uploads (credentials in the seaweedfs-s3-credentials secret)"
  value       = "https://${var.cdn_hostname}"
}
