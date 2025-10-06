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
}

mock_provider "random" {}

run "baseline" {
  command = plan

  variables {
    service_name       = "example"
    vpc_id             = "vpc-12345678"
    private_subnet_ids = ["subnet-aaaa", "subnet-bbbb"]
    public_subnet_ids  = ["subnet-1111", "subnet-2222"]
    domain_name        = "example.com"
    frontend_image     = "123456789012.dkr.ecr.us-east-1.amazonaws.com/frontend:latest"
    backend_image      = "123456789012.dkr.ecr.us-east-1.amazonaws.com/backend:latest"
  }
}
