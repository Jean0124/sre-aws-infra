# ─── EMPAQUETAR DEPENDENCIAS PYTHON ──────────────────────────────────────────
# Instala redis en un directorio temporal y lo incluye en el ZIP junto al handler
resource "null_resource" "lambda_dependencies" {
  triggers = {
    requirements = filemd5("${path.root}/lambda_src/requirements.txt")
    handler      = filemd5("${path.root}/lambda_src/handler.py")
  }

  provisioner "local-exec" {
    command = <<EOT
      pip install \
        -r ${path.root}/lambda_src/requirements.txt \
        -t ${path.root}/lambda_src/package \
        --quiet
      cp ${path.root}/lambda_src/handler.py ${path.root}/lambda_src/package/handler.py
    EOT
  }
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.root}/lambda_src/package"
  output_path = "${path.root}/lambda_src/function.zip"

  depends_on = [null_resource.lambda_dependencies]
}

# ─── IAM ROLE ─────────────────────────────────────────────────────────────────
resource "aws_iam_role" "lambda" {
  name = "${var.project}-${var.environment}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}

# Política: VPC networking + CloudWatch Logs
resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Política: S3 — solo el bucket de resultados
resource "aws_iam_role_policy" "lambda_s3" {
  name = "${var.project}-${var.environment}-lambda-s3-policy"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
        ]
        Resource = "${var.s3_bucket_arn}/results/*"
      }
    ]
  })
}

# ─── FUNCIÓN LAMBDA ───────────────────────────────────────────────────────────
resource "aws_lambda_function" "processor" {
  function_name = "${var.project}-${var.environment}-processor"
  role          = aws_iam_role.lambda.arn
  handler       = "handler.handler"
  runtime       = "python3.12"
  timeout       = 30
  memory_size   = 256

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = [var.security_group_id]
  }

  environment {
    variables = {
      REDIS_HOST    = var.redis_host
      REDIS_PORT    = tostring(var.redis_port)
      S3_BUCKET_NAME = var.s3_bucket_name
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_vpc,
    aws_iam_role_policy.lambda_s3,
  ]

  tags = {
    Name        = "${var.project}-${var.environment}-processor"
    Project     = var.project
    Environment = var.environment
  }
}

# ─── CLOUDWATCH LOG GROUP ─────────────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${aws_lambda_function.processor.function_name}"
  retention_in_days = 7

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}
