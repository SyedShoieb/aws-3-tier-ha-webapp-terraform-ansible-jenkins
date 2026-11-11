
output "vpc_id" {
  description = "ID of the project VPC"
  value       = aws_vpc.main.id
}

output "web_alb_dns_name" {
  description = "DNS name of the internet-facing web load balancer"
  value       = aws_lb.web.dns_name
}

output "web_alb_url" {
  description = "HTTP URL of the web load balancer"
  value       = "http://${aws_lb.web.dns_name}"
}

output "app_alb_dns_name" {
  description = "DNS name of the internal application load balancer"
  value       = aws_lb.app.dns_name
}

output "web_asg_name" {
  description = "Name of the web tier Auto Scaling Group"
  value       = aws_autoscaling_group.web.name
}

output "app_asg_name" {
  description = "Name of the application tier Auto Scaling Group"
  value       = aws_autoscaling_group.app.name
}

output "rds_endpoint" {
  description = "Endpoint address of the RDS database"
  value       = aws_db_instance.main.address
}

output "rds_port" {
  description = "Port used by the RDS database"
  value       = aws_db_instance.main.port
}

output "rds_secret_arn" {
  description = "ARN of the Secrets Manager secret containing the RDS master credentials"
  value       = try(aws_db_instance.main.master_user_secret[0].secret_arn, null)
}

output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name when edge services are enabled"
  value       = try(aws_cloudfront_distribution.web[0].domain_name, null)
}

output "application_url" {
  description = "Application URL; CloudFront when enabled, otherwise the web load balancer"
  value = var.enable_edge_services ? (
    "https://${aws_cloudfront_distribution.web[0].domain_name}"
    ) : (
    "http://${aws_lb.web.dns_name}"
  )
}
