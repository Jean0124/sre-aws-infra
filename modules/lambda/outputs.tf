output "invoke_arn" {
  value = aws_lambda_function.processor.invoke_arn
}

output "function_name" {
  value = aws_lambda_function.processor.function_name
}

output "function_arn" {
  value = aws_lambda_function.processor.arn
}

output "role_arn" {
  value = aws_iam_role.lambda.arn
}
