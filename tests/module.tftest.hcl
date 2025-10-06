mock_provider "aws" {
  mock_data "aws_region" {
    defaults = {
      name = "us-east-1"
    }
  }

  mock_data "aws_ec2_managed_prefix_list" {
    defaults = {
      id = "pl-123456"
    }
  }

  mock_resource "aws_lb" {
    defaults = {
      dns_name = "lb.example.com"
      zone_id  = "ZTESTALB"
      arn      = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/test/12345678"
    }
  }

  mock_resource "aws_route53_zone" {
    defaults = {
      name_servers = [
        "ns-111.awsdns-44.net",
        "ns-222.awsdns-55.com",
        "ns-333.awsdns-66.org",
        "ns-444.awsdns-77.co.uk"
      ]
    }
  }

  mock_resource "aws_cloudfront_distribution" {
    defaults = {
      domain_name = "d111111abcdef8.cloudfront.net"
    }
  }

  mock_resource "aws_acm_certificate" {
    defaults = {
      arn = "arn:aws:acm:us-east-1:123456789012:certificate/mock"
      domain_validation_options = [
        {
          domain_name          = "example.com"
          resource_record_name = "_abc.example.com"
          resource_record_type = "CNAME"
          resource_record_value = "_abc.acm-validations.aws"
        },
        {
          domain_name          = "api.example.com"
          resource_record_name = "_def.api.example.com"
          resource_record_type = "CNAME"
          resource_record_value = "_def.acm-validations.aws"
        },
        {
          domain_name          = "www.example.com"
          resource_record_name = "_ghi.www.example.com"
          resource_record_type = "CNAME"
          resource_record_value = "_ghi.acm-validations.aws"
        }
      ]
    }
  }

  mock_resource "aws_acm_certificate_validation" {
    defaults = {
      certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/mock"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
JSON
    }
  }
}

mock_provider "random" {}

run "baseline" {
  command = plan

  variables {
    service_name              = "example"
    vpc_id                    = "vpc-12345678"
    private_subnet_ids        = ["subnet-aaaa", "subnet-bbbb"]
    public_subnet_ids         = ["subnet-1111", "subnet-2222"]
    domain_name               = "example.com"
    frontend_image            = "123456789012.dkr.ecr.us-east-1.amazonaws.com/frontend:latest"
    backend_image             = "123456789012.dkr.ecr.us-east-1.amazonaws.com/backend:latest"
    cloudfront_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/app"
  }

}

run "baseline_with_external_certificate" {
  command = plan

  variables {
    service_name              = "example"
    vpc_id                    = "vpc-12345678"
    private_subnet_ids        = ["subnet-aaaa", "subnet-bbbb"]
    public_subnet_ids         = ["subnet-1111", "subnet-2222"]
    domain_name               = "example.com"
    frontend_image            = "123456789012.dkr.ecr.us-east-1.amazonaws.com/frontend:latest"
    backend_image             = "123456789012.dkr.ecr.us-east-1.amazonaws.com/backend:latest"
    certificate_arn           = "arn:aws:acm:us-east-1:123456789012:certificate/external"
    cloudfront_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/app"
  }

}

run "cloudfront_certificate_required" {
  command = plan

  variables {
    service_name              = "example"
    vpc_id                    = "vpc-12345678"
    private_subnet_ids        = ["subnet-aaaa", "subnet-bbbb"]
    public_subnet_ids         = ["subnet-1111", "subnet-2222"]
    domain_name               = "example.com"
    frontend_image            = "123456789012.dkr.ecr.us-east-1.amazonaws.com/frontend:latest"
    backend_image             = "123456789012.dkr.ecr.us-east-1.amazonaws.com/backend:latest"
    certificate_arn           = "arn:aws:acm:us-east-1:123456789012:certificate/baseline"
    cloudfront_certificate_arn = ""
  }

  expect_failures = [
    var.cloudfront_certificate_arn
  ]
}

run "cloudfront_certificate_must_be_in_virginia" {
  command = plan

  variables {
    service_name              = "example"
    vpc_id                    = "vpc-12345678"
    private_subnet_ids        = ["subnet-aaaa", "subnet-bbbb"]
    public_subnet_ids         = ["subnet-1111", "subnet-2222"]
    domain_name               = "example.com"
    frontend_image            = "123456789012.dkr.ecr.us-east-1.amazonaws.com/frontend:latest"
    backend_image             = "123456789012.dkr.ecr.us-east-1.amazonaws.com/backend:latest"
    certificate_arn           = "arn:aws:acm:us-east-1:123456789012:certificate/baseline"
    cloudfront_certificate_arn = "arn:aws:acm:eu-west-1:123456789012:certificate/frontend"
  }

  expect_failures = [
    var.cloudfront_certificate_arn
  ]
}

run "cloudfront_with_certificate" {
  command = plan

  variables {
    service_name              = "example"
    vpc_id                    = "vpc-12345678"
    private_subnet_ids        = ["subnet-aaaa", "subnet-bbbb"]
    public_subnet_ids         = ["subnet-1111", "subnet-2222"]
    domain_name               = "example.com"
    frontend_image            = "123456789012.dkr.ecr.us-east-1.amazonaws.com/frontend:latest"
    backend_image             = "123456789012.dkr.ecr.us-east-1.amazonaws.com/backend:latest"
    certificate_arn           = "arn:aws:acm:us-east-1:123456789012:certificate/baseline"
    cloudfront_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/frontend"
  }

}
