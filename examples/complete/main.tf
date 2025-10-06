module "web_app" {
  source = "../.."

  frontend_image     = "image.foo"
  backend_image      = "image.bar"
  public_subnet_ids  = module.vpc.public_subnets
  private_subnet_ids = module.vpc.private_subnets
  vpc_id             = module.vpc.default_vpc_id
  service_name       = "demo"
  domain_name        = "foo"

  backend_secrets = {
    DATABASE_USER = "${aws_secretsmanager_secret.database.arn}::DB_USER"
    DATABASE_PASS = "${aws_secretsmanager_secret.database.arn}::DB_PASS"
    DJANGO_SECRET = aws_secretsmanager_secret.django.arn
  }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "v6.4.0"

  name = "my-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway = true
}

resource "aws_secretsmanager_secret" "database" {
  name = "database"
}

resource "aws_secretsmanager_secret" "django" {
  name = "django"
}

resource "aws_secretsmanager_secret_version" "example" {
  secret_id     = aws_secretsmanager_secret.database.id
  secret_string = jsonencode({
    DB_USER = "username"
    DB_PASS = "super-secret-password"
  })
}