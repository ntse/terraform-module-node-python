locals {
  name_prefix = join("-", compact(regexall("[a-z0-9]+", lower(var.service_name))))

  base_tags = merge(
    var.tags,
    {
      "Service" = var.service_name
    }
  )

  # https://docs.aws.amazon.com/AWSCloudFormation/latest/TemplateReference/aws-properties-route53-recordset-aliastarget.html#cfn-route53-recordset-aliastarget-hostedzoneid
  cloudfront_zone_id = "Z2FDTNDATAQYW2"

  domain_name = trimsuffix(lower(trimspace(var.domain_name)), ".")
  www_domain  = "www.${local.domain_name}"

  frontend_domain  = local.domain_name
  backend_domain   = "${local.domain_name}/api"
  s3_bucket_domain = "${local.domain_name}/cdn"
}

# -----------------------------------------------------------------------------
# Networking and Load Balancer
# -----------------------------------------------------------------------------
resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb"
  description = "ALB security group"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Allow HTTP"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    prefix_list_ids = [data.aws_ec2_managed_prefix_list.cloudfront.id]
  }

  ingress {
    description     = "Allow HTTPS"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    prefix_list_ids = [data.aws_ec2_managed_prefix_list.cloudfront.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.base_tags
}

resource "aws_security_group" "frontend_tasks" {
  name        = "${local.name_prefix}-frontend"
  description = "Frontend ECS tasks"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Allow ALB to reach frontend"
    from_port       = var.frontend_port
    to_port         = var.frontend_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.base_tags
}

resource "aws_security_group" "backend_tasks" {
  name        = "${local.name_prefix}-backend"
  description = "Backend ECS tasks"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Allow ALB to reach backend"
    from_port       = var.backend_port
    to_port         = var.backend_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.base_tags
}

resource "aws_lb" "this" {
  name               = substr("${local.name_prefix}-alb", 0, 32)
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids

  tags = local.base_tags
}

resource "aws_route53_zone" "primary" {
  name    = local.domain_name
  comment = "Managed by ${var.service_name} module"

  tags = local.base_tags
}

resource "aws_acm_certificate" "alb" {
  count = var.certificate_arn == null ? 1 : 0

  domain_name               = local.domain_name
  validation_method         = "DNS"
  subject_alternative_names = var.create_www_record ? [local.www_domain] : []

  tags = local.base_tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_acm_certificate" "cloudfront" {
  region = "us-east-1"

  domain_name               = local.domain_name
  validation_method         = "DNS"
  subject_alternative_names = var.create_www_record ? [local.www_domain] : []

  tags = local.base_tags

  lifecycle {
    create_before_destroy = true
  }
}

locals {
  alb_certificate_domains = var.certificate_arn == null ? concat([local.domain_name], var.create_www_record ? [local.www_domain] : []) : []

  alb_certificate_validation_options = var.certificate_arn == null ? {
    for dvo in aws_acm_certificate.alb[0].domain_validation_options : dvo.domain_name => dvo
  } : {}
}

resource "aws_route53_record" "alb_certificate_validation" {
  count = var.certificate_arn == null ? length(local.alb_certificate_domains) : 0

  allow_overwrite = true
  name            = local.alb_certificate_validation_options[local.alb_certificate_domains[count.index]].resource_record_name
  records         = [local.alb_certificate_validation_options[local.alb_certificate_domains[count.index]].resource_record_value]
  ttl             = 60
  type            = local.alb_certificate_validation_options[local.alb_certificate_domains[count.index]].resource_record_type
  zone_id         = aws_route53_zone.primary.zone_id
}

resource "aws_acm_certificate_validation" "alb" {
  count = var.certificate_arn == null ? 1 : 0

  certificate_arn         = aws_acm_certificate.alb[0].arn
  validation_record_fqdns = [for record in aws_route53_record.alb_certificate_validation : record.fqdn]
}

locals {
  alb_certificate_arn = var.certificate_arn != null ? var.certificate_arn : aws_acm_certificate_validation.alb[0].certificate_arn
}

resource "aws_lb_target_group" "frontend" {
  name        = substr("${local.name_prefix}-fe", 0, 32)
  port        = var.frontend_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 3
    interval            = 30
    matcher             = "200-399"
    path                = var.frontend_healthcheck_path
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = local.base_tags
}

resource "aws_lb_target_group" "backend" {
  name        = substr("${local.name_prefix}-be", 0, 32)
  port        = var.backend_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 3
    interval            = 30
    matcher             = "200-399"
    path                = var.backend_healthcheck_path
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = local.base_tags
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Not Found"
      status_code  = "404"
    }
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = var.listener_ssl_policy
  certificate_arn   = local.alb_certificate_arn

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Not Found"
      status_code  = "404"
    }
  }
}

resource "aws_lb_listener_rule" "frontend_http_to_https" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 10

  action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  condition {
    host_header {
      values = concat([local.domain_name])
    }
  }
}

resource "aws_lb_listener_rule" "frontend_https" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }

  condition {
    host_header {
      values = concat([local.domain_name])
    }
  }
}

resource "aws_lb_listener_rule" "backend_http_to_https" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 20

  action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  condition {
    host_header {
      values = concat([local.domain_name])
    }
    path_pattern {
      values = ["/api/*"]
    }
  }
}

resource "aws_lb_listener_rule" "backend_https" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 20

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }

  condition {
    host_header {
      values = concat([local.domain_name])
    }
    path_pattern {
      values = ["/api/*"]
    }
  }
}

# -----------------------------------------------------------------------------
# IAM roles shared by ECS tasks
# -----------------------------------------------------------------------------
data "aws_iam_policy_document" "ecs_task_assume" {
  statement {
    effect = "Allow"

    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "task_execution" {
  name               = "${local.name_prefix}-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume.json

  tags = local.base_tags
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "frontend_task" {
  name               = "${local.name_prefix}-frontend-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume.json

  tags = local.base_tags
}

resource "aws_iam_role" "backend_task" {
  name               = "${local.name_prefix}-backend-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume.json

  tags = local.base_tags
}

resource "aws_iam_role_policy" "backend_media" {


  name = "${local.name_prefix}-media"
  role = aws_iam_role.backend_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"],
        Resource = [aws_s3_bucket.media.arn]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = ["${aws_s3_bucket.media.arn}/*"]
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Logging
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "frontend" {
  name              = "/ecs/${local.name_prefix}-frontend"
  retention_in_days = var.logs_retention_in_days

  tags = local.base_tags
}

resource "aws_cloudwatch_log_group" "backend" {
  name              = "/ecs/${local.name_prefix}-backend"
  retention_in_days = var.logs_retention_in_days

  tags = local.base_tags
}

# -----------------------------------------------------------------------------
# ECS Cluster and Services
# -----------------------------------------------------------------------------
resource "aws_ecs_cluster" "this" {
  name = "${local.name_prefix}-cluster"

  tags = local.base_tags
}

locals {
  frontend_env_map = merge(
    {
      NEXT_PUBLIC_API_URL = local.backend_domain
    },
    var.frontend_environment,
  )

  frontend_secret_map = var.frontend_secrets

  backend_env_map = merge(
    {
      FRONTEND_URL         = local.frontend_domain
      MEDIA_BUCKET_NAME    = aws_s3_bucket.media.bucket
      MEDIA_CLOUDFRONT_URL = local.frontend_domain
    },
    var.backend_environment,
  )

  backend_secret_map = var.backend_secrets
}

resource "aws_ecs_task_definition" "frontend" {
  family                   = "${local.name_prefix}-frontend"
  cpu                      = tostring(var.frontend_cpu)
  memory                   = tostring(var.frontend_memory)
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.frontend_task.arn

  container_definitions = jsonencode([
    merge(
      {
        name      = "frontend"
        image     = var.frontend_image
        essential = true
        portMappings = [
          {
            containerPort = var.frontend_port
            hostPort      = var.frontend_port
            protocol      = "tcp"
          }
        ]
        environment = [
          for k, v in local.frontend_env_map : {
            name  = k
            value = v
          }
        ]
        secrets = [
          for k, v in local.frontend_secret_map : {
            name      = k
            valueFrom = v
          }
        ]
        logConfiguration = {
          logDriver = "awslogs"
          options = {
            awslogs-group         = aws_cloudwatch_log_group.frontend.name
            awslogs-region        = data.aws_region.current.region
            awslogs-stream-prefix = "ecs"
          }
        }
      },
      var.frontend_command == null ? {} : { command = var.frontend_command }
    )
  ])

  runtime_platform {
    cpu_architecture        = "X86_64"
    operating_system_family = "LINUX"
  }

  tags = local.base_tags
}

resource "aws_ecs_task_definition" "backend" {
  family                   = "${local.name_prefix}-backend"
  cpu                      = tostring(var.backend_cpu)
  memory                   = tostring(var.backend_memory)
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.backend_task.arn

  container_definitions = jsonencode([
    merge(
      {
        name      = "backend"
        image     = var.backend_image
        essential = true
        portMappings = [
          {
            containerPort = var.backend_port
            hostPort      = var.backend_port
            protocol      = "tcp"
          }
        ]
        environment = [
          for k, v in local.backend_env_map : {
            name  = k
            value = v
          }
        ]
        secrets = [
          for k, v in local.backend_secret_map : {
            name      = k
            valueFrom = v
          }
        ]
        logConfiguration = {
          logDriver = "awslogs"
          options = {
            awslogs-group         = aws_cloudwatch_log_group.backend.name
            awslogs-region        = data.aws_region.current.region
            awslogs-stream-prefix = "ecs"
          }
        }
      },
      var.backend_command == null ? {} : { command = var.backend_command }
    )
  ])

  runtime_platform {
    cpu_architecture        = "X86_64"
    operating_system_family = "LINUX"
  }

  tags = local.base_tags
}

resource "aws_ecs_service" "frontend" {
  name            = "${local.name_prefix}-frontend"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.frontend.arn
  desired_count   = var.frontend_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.frontend_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.frontend.arn
    container_name   = "frontend"
    container_port   = var.frontend_port
  }

  lifecycle {
    ignore_changes = [desired_count]
  }

  tags = local.base_tags

  depends_on = [
    aws_lb_listener_rule.frontend_http_to_https
  ]
}

resource "aws_ecs_service" "backend" {
  name            = "${local.name_prefix}-backend"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.backend.arn
  desired_count   = var.backend_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.backend_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.backend.arn
    container_name   = "backend"
    container_port   = var.backend_port
  }

  lifecycle {
    ignore_changes = [desired_count]
  }

  tags = local.base_tags

  depends_on = [
    aws_lb_listener_rule.backend_http_to_https
  ]
}

# -----------------------------------------------------------------------------
# Autoscaling
# -----------------------------------------------------------------------------
resource "aws_appautoscaling_target" "frontend" {
  max_capacity       = var.frontend_max_capacity
  min_capacity       = var.frontend_min_capacity
  resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.frontend.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"

  depends_on = [aws_ecs_service.frontend]
}

resource "aws_appautoscaling_target" "backend" {
  max_capacity       = var.backend_max_capacity
  min_capacity       = var.backend_min_capacity
  resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.backend.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"

  depends_on = [aws_ecs_service.backend]
}

resource "aws_appautoscaling_policy" "frontend_cpu" {
  name               = "${local.name_prefix}-frontend-cpu"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.frontend.resource_id
  scalable_dimension = aws_appautoscaling_target.frontend.scalable_dimension
  service_namespace  = aws_appautoscaling_target.frontend.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }

    target_value       = var.frontend_target_cpu_utilization
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }

  depends_on = [aws_appautoscaling_target.frontend]
}

resource "aws_appautoscaling_policy" "backend_cpu" {
  name               = "${local.name_prefix}-backend-cpu"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.backend.resource_id
  scalable_dimension = aws_appautoscaling_target.backend.scalable_dimension
  service_namespace  = aws_appautoscaling_target.backend.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }

    target_value       = var.backend_target_cpu_utilization
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }

  depends_on = [aws_appautoscaling_target.backend]
}

resource "aws_appautoscaling_scheduled_action" "frontend_off_hours_down" {
  count = var.enable_off_hours_scale_down && var.off_hours_scale_down_cron != null ? 1 : 0

  name               = "${local.name_prefix}-frontend-offhours-down"
  schedule           = var.off_hours_scale_down_cron
  service_namespace  = aws_appautoscaling_target.frontend.service_namespace
  resource_id        = aws_appautoscaling_target.frontend.resource_id
  scalable_dimension = aws_appautoscaling_target.frontend.scalable_dimension
  timezone           = var.off_hours_timezone

  scalable_target_action {
    min_capacity = var.off_hours_desired_count
    max_capacity = var.off_hours_desired_count
  }

  depends_on = [aws_appautoscaling_target.frontend]
}

resource "aws_appautoscaling_scheduled_action" "frontend_off_hours_up" {
  count = var.enable_off_hours_scale_down && var.off_hours_scale_up_cron != null ? 1 : 0

  name               = "${local.name_prefix}-frontend-offhours-up"
  schedule           = var.off_hours_scale_up_cron
  service_namespace  = aws_appautoscaling_target.frontend.service_namespace
  resource_id        = aws_appautoscaling_target.frontend.resource_id
  scalable_dimension = aws_appautoscaling_target.frontend.scalable_dimension
  timezone           = var.off_hours_timezone

  scalable_target_action {
    min_capacity = var.frontend_min_capacity
    max_capacity = var.frontend_max_capacity
  }

  depends_on = [aws_appautoscaling_target.frontend]
}

resource "aws_appautoscaling_scheduled_action" "backend_off_hours_down" {
  count = var.enable_off_hours_scale_down && var.off_hours_scale_down_cron != null ? 1 : 0

  name               = "${local.name_prefix}-backend-offhours-down"
  schedule           = var.off_hours_scale_down_cron
  service_namespace  = aws_appautoscaling_target.backend.service_namespace
  resource_id        = aws_appautoscaling_target.backend.resource_id
  scalable_dimension = aws_appautoscaling_target.backend.scalable_dimension
  timezone           = var.off_hours_timezone

  scalable_target_action {
    min_capacity = var.off_hours_desired_count
    max_capacity = var.off_hours_desired_count
  }

  depends_on = [aws_appautoscaling_target.backend]
}

resource "aws_appautoscaling_scheduled_action" "backend_off_hours_up" {
  count = var.enable_off_hours_scale_down && var.off_hours_scale_up_cron != null ? 1 : 0

  name               = "${local.name_prefix}-backend-offhours-up"
  schedule           = var.off_hours_scale_up_cron
  service_namespace  = aws_appautoscaling_target.backend.service_namespace
  resource_id        = aws_appautoscaling_target.backend.resource_id
  scalable_dimension = aws_appautoscaling_target.backend.scalable_dimension
  timezone           = var.off_hours_timezone

  scalable_target_action {
    min_capacity = var.backend_min_capacity
    max_capacity = var.backend_max_capacity
  }

  depends_on = [aws_appautoscaling_target.backend]
}

# -----------------------------------------------------------------------------
#  CloudFront distribution
# -----------------------------------------------------------------------------
resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  is_ipv6_enabled     = true
  price_class         = var.cloudfront_price_class
  wait_for_deployment = false

  aliases = concat(
    [local.frontend_domain],
    var.create_www_record ? [local.www_domain] : []
  )

  origin {
    domain_name = aws_lb.this.dns_name
    origin_id   = "alb"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  origin {
    domain_name              = aws_s3_bucket.media.bucket_regional_domain_name
    origin_id                = "media-bucket"
    origin_access_control_id = aws_cloudfront_origin_access_control.media.id
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "alb"

    viewer_protocol_policy = var.cloudfront_viewer_protocol_policy

    forwarded_values {
      query_string = true
      headers      = ["Host", "Authorization"]

      cookies {
        forward = "all"
      }
    }

    min_ttl     = 0
    default_ttl = 1200
    max_ttl     = 31536000
  }


  ordered_cache_behavior {
    path_pattern     = "/api/*"
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = "alb"

    forwarded_values {
      query_string = false
      headers      = ["Host", "Authorization"]

      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 300
    max_ttl                = 31536000
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }

  ordered_cache_behavior {
    path_pattern     = "/cdn/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = "media-bucket"

    forwarded_values {
      query_string = true

      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.cloudfront.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = local.base_tags

  depends_on = [aws_lb.this]
}

resource "aws_cloudfront_origin_access_control" "media" {


  name                              = "${local.name_prefix}-media"
  description                       = "Access control for ${local.name_prefix} media bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

locals {
  cloudfront_domain_name = aws_cloudfront_distribution.this.domain_name
  cloudfront_alias_zone  = local.cloudfront_zone_id
}

# -----------------------------------------------------------------------------
# Route53 records
# -----------------------------------------------------------------------------
resource "aws_route53_record" "a" {
  zone_id = aws_route53_zone.primary.zone_id
  name    = local.domain_name
  type    = "A"

  alias {
    name                   = local.cloudfront_domain_name
    zone_id                = local.cloudfront_alias_zone
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "aaaa" {
  zone_id = aws_route53_zone.primary.zone_id
  name    = local.domain_name
  type    = "AAAA"

  alias {
    name                   = local.cloudfront_domain_name
    zone_id                = local.cloudfront_alias_zone
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "www_a" {
  count   = var.create_www_record ? 1 : 0
  zone_id = aws_route53_zone.primary.zone_id
  name    = local.www_domain
  type    = "A"

  alias {
    name                   = local.cloudfront_domain_name
    zone_id                = local.cloudfront_alias_zone
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "www_aaaa" {
  count   = var.create_www_record ? 1 : 0
  zone_id = aws_route53_zone.primary.zone_id
  name    = local.www_domain
  type    = "AAAA"

  alias {
    name                   = local.cloudfront_domain_name
    zone_id                = local.cloudfront_alias_zone
    evaluate_target_health = false
  }
}

# -----------------------------------------------------------------------------
# Media bucket protected by CloudFront
# -----------------------------------------------------------------------------
resource "random_string" "media" {
  length  = 6
  upper   = false
  special = false
}

resource "aws_s3_bucket" "media" {
  bucket = var.media_bucket_name != null ? var.media_bucket_name : "${local.name_prefix}-media-${random_string.media.result}"

  force_destroy = var.media_bucket_force_destroy

  tags = local.base_tags
}

resource "aws_s3_bucket_versioning" "media" {
  bucket = aws_s3_bucket.media.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "media" {
  bucket = aws_s3_bucket.media.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "media" {
  bucket = aws_s3_bucket.media.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "media" {
  bucket = aws_s3_bucket.media.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_policy" "media" {
  bucket = aws_s3_bucket.media.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.media.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.this.arn
          }
        }
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Supporting data sources
# -----------------------------------------------------------------------------
data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

data "aws_region" "current" {}
