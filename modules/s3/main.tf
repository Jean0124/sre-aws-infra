resource "aws_s3_bucket" "results" {
  bucket        = "${var.project}-${var.environment}-results-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  tags = {
    Name        = "${var.project}-${var.environment}-results"
    Project     = var.project
    Environment = var.environment
  }
}

data "aws_caller_identity" "current" {}

# ─── BLOCK PUBLIC ACCESS (las 4 configuraciones) ─────────────────────────────
resource "aws_s3_bucket_public_access_block" "results" {
  bucket = aws_s3_bucket.results.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ─── VERSIONADO ──────────────────────────────────────────────────────────────
resource "aws_s3_bucket_versioning" "results" {
  bucket = aws_s3_bucket.results.id

  versioning_configuration {
    status = "Enabled"
  }
}

# ─── CIFRADO EN REPOSO ───────────────────────────────────────────────────────
resource "aws_s3_bucket_server_side_encryption_configuration" "results" {
  bucket = aws_s3_bucket.results.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
