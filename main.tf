provider "aws" {
}

resource "random_id" "id" {
  byte_length = 8
}

resource "aws_s3_bucket" "images" {
  force_destroy = "true"
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "/tmp/lambda-${random_id.id.hex}.zip"
	source {
    content  = file("index.mjs")
    filename = "index.mjs"
  }
}

resource "aws_lambda_function" "backend" {
  function_name    = "backend-${random_id.id.hex}"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  environment {
    variables = {
      IMAGES_BUCKET: aws_s3_bucket.images.bucket,
			SECRET_ACCESS_KEY_PARAMETER = module.access_key.parameter_name
			ACCESS_KEY_ID = jsondecode(module.access_key.outputs).AccessKeyId
    }
  }
  timeout = 30
  handler = "index.handler"
  runtime = "nodejs18.x"
  role    = aws_iam_role.backend_exec.arn
}

data "aws_iam_policy_document" "backend" {
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      "arn:aws:logs:*:*:*"
    ]
  }
  statement {
    actions = [
      "s3:GetObject",
    ]
    resources = [
      "${aws_s3_bucket.images.arn}/*"
    ]
  }
  statement {
    actions = [
      "ssm:GetParameter",
    ]
    resources = [
			module.access_key.parameter_arn
    ]
  }
}

resource "aws_cloudwatch_log_group" "backend" {
  name              = "/aws/lambda/${aws_lambda_function.backend.function_name}"
  retention_in_days = 14
}

resource "aws_iam_role_policy" "backend" {
  role   = aws_iam_role.backend_exec.id
  policy = data.aws_iam_policy_document.backend.json
}

resource "aws_iam_role" "backend_exec" {
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_lambda_function_url" "backend" {
  function_name      = aws_lambda_function.backend.function_name
  authorization_type = "NONE"
}

output "url" {
	value = aws_lambda_function_url.backend.function_url
}
