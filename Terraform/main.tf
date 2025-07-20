terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.67.0"
    }
  }

  required_version = ">= 1.4.0"
}

provider "aws" {
  region = "ap-south-1"
}

resource "aws_s3_bucket" "data_bucket" {
  bucket = var.bucket_name

  tags = {
    Name        = var.bucket_name
    Environment = "Dev"
  }
}

resource "aws_s3_object" "raw_folder" {
  bucket = aws_s3_bucket.data_bucket.id
  key    = "raw/"
  acl    = "private"
}

resource "aws_s3_object" "analysis_folder" {
  bucket = aws_s3_bucket.data_bucket.id
  key    = "analysis/"
  acl    = "private"
}

resource "aws_s3_object" "processed_folder" {
  bucket = aws_s3_bucket.data_bucket.id
  key    = "processed/"
  acl    = "private"
}

resource "aws_athena_workgroup" "default" {
  name = "bellybrew_workgroup"

  configuration {
    result_configuration {
      output_location = "s3://${var.bucket_name}/analysis/"
    }
  }

  state = "ENABLED"
}

resource "aws_athena_database" "bellybrew_db" {
  name   = "bellybrewanalysis_db"
  bucket = var.bucket_name
}

resource "aws_athena_named_query" "select_db" {
  name        = "SelectDatabase"
  database    = aws_athena_database.bellybrew_db.name
  query       = "USE bellybrewanalysis_db;"
  workgroup   = aws_athena_workgroup.default.name
  description = "Query to select the Athena database"
}

resource "aws_iam_role" "lambda_role" {
  name = "belly-brew-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Principal = {
          Service = "lambda.amazonaws.com"
        },
        Effect = "Allow",
        Sid    = ""
      }
    ]
  })
}

resource "aws_iam_policy" "belly_brew_policy" {
  name        = "belly-brew-iam-policy"
  description = "IAM Policy for Lambda with S3, Athena, CloudWatch, and API Gateway access"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = "s3:*",
        Resource = "*"
      },
      {
        Effect   = "Allow",
        Action   = "athena:*",
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*"
      },
      {
        Effect   = "Allow",
        Action   = "apigateway:*",
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_policy" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.belly_brew_policy.arn
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/lambda_function.zip"
}

resource "aws_lambda_function" "bellybrew_athena_function" {
  function_name = "bellybrew-athena-function"
  role          = aws_iam_role.lambda_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"
  filename      = data.archive_file.lambda_zip.output_path
  timeout       = 60

  environment {
    variables = {
      ATHENA_OUTPUT_LOCATION = "s3://${var.bucket_name}/athena/"
    }
  }

  depends_on = [aws_iam_role.lambda_role]
}

resource "aws_cloudwatch_event_rule" "scheduler" {
  name                = "bellybrew-daily-trigger"
  description         = "Trigger Lambda every day at 10 PM"
  schedule_expression = "cron(0 22 * * ? *)"
  state               = "ENABLED"
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.scheduler.name
  target_id = "bellybrew-athena-lambda"
  arn       = aws_lambda_function.bellybrew_athena_function.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.bellybrew_athena_function.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.scheduler.arn
}