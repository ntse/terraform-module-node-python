output "cluster_id" {
  description = "ID of the ECS cluster."
  value       = aws_ecs_cluster.this.id
}

output "cluster_name" {
  description = "Name of the ECS cluster."
  value       = aws_ecs_cluster.this.name
}

output "frontend_service_name" {
  description = "Name of the ECS service running the frontend."
  value       = aws_ecs_service.frontend.name
}

output "backend_service_name" {
  description = "Name of the ECS service running the backend."
  value       = aws_ecs_service.backend.name
}

output "load_balancer_arn" {
  description = "ARN of the application load balancer."
  value       = aws_lb.this.arn
}

output "load_balancer_dns_name" {
  description = "DNS name of the application load balancer."
  value       = aws_lb.this.dns_name
}

output "alb_certificate_arn" {
  description = "ARN of the ACM certificate attached to the ALB listener."
  value       = local.alb_certificate_arn
}

output "hosted_zone_id" {
  description = "ID of the Route53 hosted zone managed by the module."
  value       = aws_route53_zone.primary.zone_id
}

output "hosted_zone_name_servers" {
  description = "Name servers assigned to the hosted zone."
  value       = aws_route53_zone.primary.name_servers
}

output "frontend_target_group_arn" {
  description = "ARN of the frontend target group."
  value       = aws_lb_target_group.frontend.arn
}

output "backend_target_group_arn" {
  description = "ARN of the backend target group."
  value       = aws_lb_target_group.backend.arn
}

output "media_bucket_name" {
  description = "Name of the media bucket."
  value       = aws_s3_bucket.media.bucket
}

output "cloudfront_domain_name" {
  description = "Domain name of the CloudFront distribution serving the application and media."
  value       = aws_cloudfront_distribution.this.domain_name
}