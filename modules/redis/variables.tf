variable "project" {
  description = "Nombre del proyecto — se usa como prefijo en todos los recursos"
  type        = string
}

variable "environment" {
  description = "Entorno de despliegue (dev, staging, prod)"
  type        = string
}

variable "subnet_ids" {
  description = "IDs de las subnets privadas donde se desplegara ElastiCache"
  type        = list(string)
}

variable "security_group_id" {
  description = "ID del Security Group de Redis"
  type        = string
}
