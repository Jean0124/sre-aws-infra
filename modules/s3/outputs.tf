output "bucket_name" {
  value = aws_s3_bucket.results.bucket
}

output "bucket_arn" {
  value = aws_s3_bucket.results.arn
}
