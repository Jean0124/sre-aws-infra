output "api_endpoint" {
  description = "URL pública del API Gateway"
  value       = module.api_gateway.api_endpoint
}

output "s3_bucket_name" {
  description = "Nombre del bucket S3"
  value       = module.s3.bucket_name
}

output "redis_endpoint" {
  description = "Endpoint de Redis (solo accesible desde dentro de la VPC)"
  value       = module.redis.redis_endpoint
}

output "lambda_function_name" {
  description = "Nombre de la función Lambda"
  value       = module.lambda.function_name
}
