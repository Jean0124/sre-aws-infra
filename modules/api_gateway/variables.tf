variable "project" {
  description = "Nombre del proyecto — se usa como prefijo en todos los recursos"
  type        = string
}

variable "environment" {
  description = "Entorno de despliegue (dev, staging, prod)"
  type        = string
}

variable "lambda_invoke_arn" {
  description = "ARN de invocacion de la funcion Lambda para la integracion proxy"
  type        = string
}

variable "lambda_function_name" {
  description = "Nombre de la funcion Lambda para el permiso de invocacion"
  type        = string
}
