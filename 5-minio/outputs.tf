output "cdn_urls" {
  description = "Base URL per public CDN bucket"
  value       = { for name in var.bucket_names : name => "https://${var.cdn_hostname}/${name}" }
}

output "console_url" {
  description = "URL for the MinIO admin console"
  value       = "https://${var.console_hostname}"
}

output "s3_endpoint" {
  description = "S3 API endpoint (for aws-cli / rclone / the uploader tool)"
  value       = "https://${var.cdn_hostname}"
}
