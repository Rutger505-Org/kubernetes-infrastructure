output "cdn_url" {
  description = "Base URL for the public CDN bucket"
  value       = "https://${var.cdn_hostname}/${var.bucket_name}"
}

output "console_url" {
  description = "URL for the MinIO admin console"
  value       = "https://${var.console_hostname}"
}

output "s3_endpoint" {
  description = "S3 API endpoint (for aws-cli / rclone / the uploader tool)"
  value       = "https://${var.cdn_hostname}"
}
