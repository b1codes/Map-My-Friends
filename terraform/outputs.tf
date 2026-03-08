output "frontend_url" {
  description = "The URL of the frontend CloudFront distribution"
  value       = "https://${aws_cloudfront_distribution.frontend.domain_name}"
}

output "backend_public_ip" {
  description = "The public IP of the backend EC2 instance"
  value       = aws_instance.backend.public_ip
}

output "s3_bucket_name" {
  description = "The name of the S3 bucket for the frontend"
  value       = aws_s3_bucket.frontend.id
}
