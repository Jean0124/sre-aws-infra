variable "project" {
  description = "Nombre del proyecto — se usa como prefijo en todos los recursos"
  type        = string
}

variable "environment" {
  description = "Entorno de despliegue (dev, staging, prod)"
  type        = string
}

variable "subnet_ids" {
  description = "IDs de las subnets privadas donde se desplegara la funcion Lambda"
  type        = list(string)
}

variable "security_group_id" {
  description = "ID del Security Group de Lambda"
  type        = string
}

variable "redis_host" {
  description = "Endpoint del cluster ElastiCache Redis"
  type        = string
}

variable "redis_port" {
  description = "Puerto de Redis"
  type        = number
  default     = 6379
}

variable "s3_bucket_name" {
  description = "Nombre del bucket S3 donde se guardan los resultados"
  type        = string
}

variable "s3_bucket_arn" {
  description = "ARN del bucket S3 para la politica IAM de la funcion"
  type        = string
}
