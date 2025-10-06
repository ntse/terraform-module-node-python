variable "service_name" {
  description = "Base name used for tagging and resource naming."
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC where the services will run."
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for ECS services."
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for the load balancer."
  type        = list(string)
}

variable "domain_name" {
  description = "Primary domain name managed by the module (e.g. example.com)."
  type        = string
}

variable "create_www_record" {
  description = "Whether to create a www.<domain> alias that points to the frontend."
  type        = bool
  default     = true
}

variable "frontend_image" {
  description = "Container image for the Next.js frontend."
  type        = string
}

variable "backend_image" {
  description = "Container image for the Python backend."
  type        = string
}

variable "frontend_port" {
  description = "Container port exposed by the frontend application."
  type        = number
  default     = 3000
}

variable "backend_port" {
  description = "Container port exposed by the backend API."
  type        = number
  default     = 8000
}

variable "frontend_desired_count" {
  description = "Desired number of frontend tasks."
  type        = number
  default     = 2
}

variable "backend_desired_count" {
  description = "Desired number of backend tasks."
  type        = number
  default     = 2
}

variable "frontend_min_capacity" {
  description = "Minimum number of frontend tasks allowed by autoscaling."
  type        = number
  default     = 1
}

variable "frontend_max_capacity" {
  description = "Maximum number of frontend tasks allowed by autoscaling."
  type        = number
  default     = 4
}

variable "frontend_target_cpu_utilization" {
  description = "Target average CPU utilization percentage for frontend autoscaling."
  type        = number
  default     = 50
}

variable "backend_min_capacity" {
  description = "Minimum number of backend tasks allowed by autoscaling."
  type        = number
  default     = 1
}

variable "backend_max_capacity" {
  description = "Maximum number of backend tasks allowed by autoscaling."
  type        = number
  default     = 4
}

variable "backend_target_cpu_utilization" {
  description = "Target average CPU utilization percentage for backend autoscaling."
  type        = number
  default     = 50
}

variable "frontend_cpu" {
  description = "CPU units for the frontend task definition."
  type        = number
  default     = 512
}

variable "frontend_memory" {
  description = "Memory (MiB) for the frontend task definition."
  type        = number
  default     = 1024
}

variable "backend_cpu" {
  description = "CPU units for the backend task definition."
  type        = number
  default     = 512
}

variable "frontend_healthcheck_path" {
  description = "HTTP path used by the load balancer to health check the frontend service."
  type        = string
  default     = "/"
}

variable "backend_healthcheck_path" {
  description = "HTTP path used by the load balancer to health check the backend service."
  type        = string
  default     = "/health"
}

variable "backend_memory" {
  description = "Memory (MiB) for the backend task definition."
  type        = number
  default     = 1024
}

variable "frontend_environment" {
  description = "Extra environment variables for the frontend container."
  type        = map(string)
  default     = {}
}

variable "backend_environment" {
  description = "Extra environment variables for the backend container."
  type        = map(string)
  default     = {}
}

variable "frontend_command" {
  description = "Optional override for the frontend container command."
  type        = list(string)
  default     = null
}

variable "backend_command" {
  description = "Optional override for the backend container command."
  type        = list(string)
  default     = null
}

variable "certificate_arn" {
  description = "Optional override ACM certificate ARN for the ALB. Leave null to let the module provision and validate one automatically."
  type        = string
  default     = null
}

variable "listener_ssl_policy" {
  description = "SSL policy for the HTTPS listener."
  type        = string
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}

variable "logs_retention_in_days" {
  description = "Retention for CloudWatch log groups."
  type        = number
  default     = 30
}

variable "media_bucket_name" {
  description = "Optional custom name for the media bucket. Defaults to a name derived from service_name."
  type        = string
  default     = null
}

variable "media_bucket_force_destroy" {
  description = "If true, delete all objects when destroying the media bucket."
  type        = bool
  default     = false
}

variable "enable_off_hours_scale_down" {
  description = "Whether to schedule services to scale down outside office hours."
  type        = bool
  default     = false
}

variable "off_hours_scale_down_cron" {
  description = "Cron expression (CloudWatch Events format) indicating when to scale services down. Required if off-hours scaling is enabled."
  type        = string
  default     = null
}

variable "off_hours_scale_up_cron" {
  description = "Cron expression (CloudWatch Events format) indicating when to restore normal capacity. Required if off-hours scaling is enabled."
  type        = string
  default     = null
}

variable "off_hours_timezone" {
  description = "Timezone used for scheduled off-hours scaling actions."
  type        = string
  default     = "UTC"
}

variable "off_hours_desired_count" {
  description = "Desired task count during off-hours scale down (applied to both services)."
  type        = number
  default     = 0
}

variable "cloudfront_price_class" {
  description = "Price class for the frontend CloudFront distribution."
  type        = string
  default     = "PriceClass_100"
}

variable "cloudfront_viewer_protocol_policy" {
  description = "Viewer protocol policy for the frontend CloudFront distribution."
  type        = string
  default     = "redirect-to-https"
}

variable "tags" {
  description = "Tags to apply to all created resources."
  type        = map(string)
  default     = {}
}

variable "frontend_secrets" {
  description = "Secrets to inject into the frontend container (name to AWS Secrets Manager ARN or SSM parameter)."
  type        = map(string)
  default     = {}
}

variable "backend_secrets" {
  description = "Secrets to inject into the backend container (name to AWS Secrets Manager ARN or SSM parameter)."
  type        = map(string)
  default     = {}
}
