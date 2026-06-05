variable "project" {
  description = "Nombre del proyecto — se usa como prefijo en todos los recursos"
  type        = string
}

variable "environment" {
  description = "Entorno de despliegue (dev, staging, prod)"
  type        = string
}
