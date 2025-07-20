output "s3_bucket_name" {
  value = aws_s3_bucket.data_bucket.bucket
}

output "lambda_function_name" {
  value = aws_lambda_function.bellybrew_athena_function.function_name
}

output "athena_database_name" {
  value = aws_athena_database.bellybrew_db.name
}