# terraform-module-node-python

Opinionated Terraform module for deploying a containerised Next.js frontend and Python backend on AWS Fargate. It provisions an application load balancer locked down to CloudFront, a public hosted zone, a required S3 media bucket, and a single CloudFront distribution that fronts both the application and media paths.

## Features

- ECS Fargate cluster with dedicated task definitions for frontend and backend containers
- Application Load Balancer restricted to the CloudFront managed prefix list
- DNS-validated ACM certificate for the ALB issued automatically (override supported)
- Public Route53 hosted zone with apex/(and optionally `www`) pointed at CloudFront
- S3 media bucket locked behind CloudFront origin access control. Allows Public users to view and the Backend to Write and Delete files.
- Single CloudFront distribution that serves the site, API, and media paths with configurable caching
- Target-tracking autoscaling for both services with optional scheduled off-hours scale downs
- Structured CloudWatch logging for the services

## High-Level Architecture

1. **Networking:** An application load balancer in the provided VPC/public subnets and security groups that only allow traffic from the ALB to the tasks.
2. **Compute:** Separate ECS Fargate services for the Next.js frontend and Python backend, each with configurable scaling and container settings.
3. **Routing:** Host-based listener rules map apex traffic to the frontend service and `api.<domain>` traffic to the backend service.
4. **DNS:** A public Route53 hosted zone is created for the supplied domain with ALIAS records for apex/`www`, `api`, and `cdn` endpoints.
5. **Media:** An S3 bucket for media assets is fronted by the shared CloudFront distribution using origin access control. The backend task role gets scoped S3 permissions while public access is restricted to CloudFront.

## Usage

```hcl
module "app" {
  source = "./terraform-module-node-python"

  service_name        = "my-app"
  vpc_id              = "vpc-1234567890abcdef0"
  private_subnet_ids  = ["subnet-111", "subnet-222"]
  public_subnet_ids   = ["subnet-aaa", "subnet-bbb"]
  domain_name         = "example.com"
  frontend_image      = "123456789012.dkr.ecr.us-east-1.amazonaws.com/frontend:latest"
  backend_image       = "123456789012.dkr.ecr.us-east-1.amazonaws.com/backend:latest"

  media_bucket_force_destroy = false

  tags = {
    Environment = "production"
    Owner       = "platform"
  }
}
```

The module exposes the ALB DNS name and ECS service identifiers so you can integrate with Route53, CI/CD pipelines, or autoscaling policies outside the module.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `service_name` | Base name used for tagging and resource naming. | `string` | n/a | yes |
| `vpc_id` | ID of the VPC where the services will run. | `string` | n/a | yes |
| `private_subnet_ids` | List of private subnet IDs for ECS services. | `list(string)` | n/a | yes |
| `public_subnet_ids` | List of public subnet IDs for the load balancer. | `list(string)` | n/a | yes |
| `domain_name` | Primary domain name managed by the module (e.g. `example.com`). | `string` | n/a | yes |
| `create_www_record` | Create a `www.` alias alongside the apex frontend record. | `bool` | `true` | no |
| `frontend_image` | Container image for the Next.js frontend. | `string` | n/a | yes |
| `backend_image` | Container image for the Python backend. | `string` | n/a | yes |
| `frontend_port` | Container port exposed by the frontend. | `number` | `3000` | no |
| `backend_port` | Container port exposed by the backend. | `number` | `8000` | no |
| `frontend_desired_count` | Desired number of frontend tasks. | `number` | `2` | no |
| `backend_desired_count` | Desired number of backend tasks. | `number` | `2` | no |
| `frontend_min_capacity` | Minimum number of frontend tasks allowed by autoscaling. | `number` | `1` | no |
| `frontend_max_capacity` | Maximum number of frontend tasks allowed by autoscaling. | `number` | `4` | no |
| `frontend_target_cpu_utilization` | Target CPU utilisation percentage for frontend autoscaling. | `number` | `50` | no |
| `backend_min_capacity` | Minimum number of backend tasks allowed by autoscaling. | `number` | `1` | no |
| `backend_max_capacity` | Maximum number of backend tasks allowed by autoscaling. | `number` | `4` | no |
| `backend_target_cpu_utilization` | Target CPU utilisation percentage for backend autoscaling. | `number` | `50` | no |
| `frontend_cpu` | CPU units for the frontend task. | `number` | `512` | no |
| `frontend_memory` | Memory (MiB) for the frontend task. | `number` | `1024` | no |
| `backend_cpu` | CPU units for the backend task. | `number` | `512` | no |
| `backend_memory` | Memory (MiB) for the backend task. | `number` | `1024` | no |
| `frontend_environment` | Extra environment variables for the frontend container. | `map(string)` | `{}` | no |
| `backend_environment` | Extra environment variables for the backend container. | `map(string)` | `{}` | no |
| `frontend_command` | Override command for the frontend container. | `list(string)` | `null` | no |
| `backend_command` | Override command for the backend container. | `list(string)` | `null` | no |
| `frontend_healthcheck_path` | HTTP path for frontend health checks. | `string` | `/` | no |
| `backend_healthcheck_path` | HTTP path for backend health checks. | `string` | `/health` | no |
| `certificate_arn` | Optional override ACM certificate ARN for the ALB. | `string` | `null` | no |
| `listener_ssl_policy` | SSL policy for the HTTPS listener. | `string` | `ELBSecurityPolicy-TLS13-1-2-2021-06` | no |
| `logs_retention_in_days` | Retention for CloudWatch log groups. | `number` | `30` | no |
| `media_bucket_name` | Custom name for the media bucket. | `string` | `null` | no |
| `media_bucket_force_destroy` | Destroy bucket objects on teardown. | `bool` | `false` | no |
| `enable_off_hours_scale_down` | Enable scheduled scale down of both services outside office hours. | `bool` | `false` | no |
| `off_hours_scale_down_cron` | CloudWatch Events cron expression describing when to scale down. | `string` | `null` | no |
| `off_hours_scale_up_cron` | CloudWatch Events cron expression describing when to restore normal capacity. | `string` | `null` | no |
| `off_hours_timezone` | Timezone for scheduled off-hours scaling actions. | `string` | `"UTC"` | no |
| `off_hours_desired_count` | Desired tasks per service during off-hours. | `number` | `0` | no |
| `cloudfront_price_class` | Price class for the CloudFront distribution. | `string` | `PriceClass_100` | no |
| `cloudfront_viewer_protocol_policy` | Viewer protocol policy for the CloudFront distribution. | `string` | `redirect-to-https` | no |
| `frontend_secrets` | Map of secret name to value source ARN/parameter for the frontend container. | `map(string)` | `{}` | no |
| `backend_secrets` | Map of secret name to value source ARN/parameter for the backend container. | `map(string)` | `{}` | no |
| `tags` | Tags to apply to created resources. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| `cluster_id` | ID of the ECS cluster. |
| `cluster_name` | Name of the ECS cluster. |
| `frontend_service_name` | Name of the frontend ECS service. |
| `backend_service_name` | Name of the backend ECS service. |
| `load_balancer_arn` | ARN of the application load balancer. |
| `load_balancer_dns_name` | DNS name of the application load balancer. |
| `alb_certificate_arn` | ARN of the ACM certificate attached to the ALB. |
| `hosted_zone_id` | ID of the managed Route53 hosted zone. |
| `hosted_zone_name_servers` | Name servers assigned to the hosted zone. |
| `frontend_target_group_arn` | ARN of the frontend target group. |
| `backend_target_group_arn` | ARN of the backend target group. |
| `media_bucket_name` | Name of the media bucket. |
| `cloudfront_domain_name` | Domain name of the CloudFront distribution. |
| `frontend_fqdn` | Apex FQDN serving the frontend. |
| `api_fqdn` | FQDN serving the backend API. |
| `cdn_fqdn` | FQDN serving static media. |

## Notes

- Delegate the domain to Route53 by updating your registrar with the `hosted_zone_name_servers` output after the first apply.
- The module provisions and validates an ACM certificate for the ALB automatically unless you provide `certificate_arn`.
- The backend container receives media bucket information (`MEDIA_BUCKET_NAME`, `MEDIA_CLOUDFRONT_URL`) and the frontend container receives API host variables out of the box.
- Database resources remain outside the module's scope.

## Testing

- Run `terraform test` to execute mocked plan tests that cover the baseline configuration and CloudFront validation rules.
# terraform-module-node-python
