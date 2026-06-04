# ─── HTTP API ─────────────────────────────────────────────────────────────────
# Elegimos HTTP API (v2) sobre REST API por:
# - Menor latencia (~60% más rápido en cold starts)
# - Costo más bajo (~70% más barato por request)
# - CORS y throttling nativos sin recursos extra
# - Integración proxy simplificada con Lambda
# REST API solo se justificaría si necesitáramos API keys, usage plans, o request/response mapping avanzado
resource "aws_apigatewayv2_api" "main" {
  name          = "${var.project}-${var.environment}-api"
  protocol_type = "HTTP"
  description   = "API Gateway HTTP para el servicio de procesamiento de datos"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["POST", "OPTIONS"]
    allow_headers = ["Content-Type", "X-Cache"]
    max_age       = 300
  }

  tags = {
    Name        = "${var.project}-${var.environment}-api"
    Project     = var.project
    Environment = var.environment
  }
}

# ─── INTEGRACIÓN CON LAMBDA ──────────────────────────────────────────────────
resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.lambda_invoke_arn
  payload_format_version = "2.0"
}

# ─── RUTA POST /process ───────────────────────────────────────────────────────
resource "aws_apigatewayv2_route" "process" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "POST /process"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

# ─── CLOUDWATCH LOG GROUP PARA ACCESS LOGS ───────────────────────────────────
resource "aws_cloudwatch_log_group" "api_gw" {
  name              = "/aws/apigateway/${var.project}-${var.environment}"
  retention_in_days = 7

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}

# ─── STAGE CON THROTTLING Y ACCESS LOGS ──────────────────────────────────────
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_rate_limit  = 100   # requests por segundo
    throttling_burst_limit = 200   # burst máximo
    logging_level          = "OFF" # logging se maneja via access_log_settings
  }

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      sourceIp       = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      protocol       = "$context.protocol"
      httpMethod     = "$context.httpMethod"
      resourcePath   = "$context.resourcePath"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      responseLength = "$context.responseLength"
      integrationLatency = "$context.integrationLatency"
    })
  }

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}

# ─── PERMISO PARA QUE API GATEWAY INVOQUE LAMBDA ─────────────────────────────
resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}
