terraform {
  required_version = ">= 1.3.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

module "vpc" {
  source      = "./modules/vpc"
  project     = var.project
  environment = var.environment
  vpc_cidr    = var.vpc_cidr
  aws_region  = var.aws_region
}

module "s3" {
  source      = "./modules/s3"
  project     = var.project
  environment = var.environment
}

module "redis" {
  source             = "./modules/redis"
  project            = var.project
  environment        = var.environment
  subnet_ids         = module.vpc.private_subnet_ids
  security_group_id  = module.vpc.redis_sg_id
}

module "lambda" {
  source              = "./modules/lambda"
  project             = var.project
  environment         = var.environment
  subnet_ids          = module.vpc.private_subnet_ids
  security_group_id   = module.vpc.lambda_sg_id
  redis_host          = module.redis.redis_endpoint
  redis_port          = 6379
  s3_bucket_name      = module.s3.bucket_name
  s3_bucket_arn       = module.s3.bucket_arn
}

module "api_gateway" {
  source             = "./modules/api_gateway"
  project            = var.project
  environment        = var.environment
  lambda_invoke_arn  = module.lambda.invoke_arn
  lambda_function_name = module.lambda.function_name
}
