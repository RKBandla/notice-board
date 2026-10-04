locals {
  name          = "student-${var.student_name}-notice-board"
  function_name = "${local.name}-backend"
  create_role   = var.lambda_role_arn == ""
  role_arn      = local.create_role ? aws_iam_role.lambda_exec[0].arn : var.lambda_role_arn
}

# =====================================================================
# 1. FRONTEND: S3 BUCKET
#    Tier 1 -> public static website.  Tier 3 -> private, CloudFront only.
# =====================================================================
resource "aws_s3_bucket" "frontend" {
  bucket        = "${local.name}-frontend"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket                  = aws_s3_bucket.frontend.id
  block_public_acls       = var.enable_cloudfront
  block_public_policy     = var.enable_cloudfront
  ignore_public_acls      = var.enable_cloudfront
  restrict_public_buckets = var.enable_cloudfront
}

resource "aws_s3_bucket_website_configuration" "frontend" {
  count  = var.enable_cloudfront ? 0 : 1
  bucket = aws_s3_bucket.frontend.id

  index_document { suffix = "index.html" }
  error_document { key = "index.html" }
}

resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  policy = var.enable_cloudfront ? jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowCloudFrontServicePrincipal"
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.frontend.arn}/*"
      Condition = {
        StringEquals = { "AWS:SourceArn" = aws_cloudfront_distribution.cdn[0].arn }
      }
    }]
    }) : jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "PublicReadGetObject"
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.frontend.arn}/*"
    }]
  })

  # The public-access settings must change before the policy does.
  depends_on = [aws_s3_bucket_public_access_block.frontend]
}

# =====================================================================
# 2. BACKEND: IAM ROLE (own account only) & LAMBDA FUNCTION
# =====================================================================
resource "aws_iam_role" "lambda_exec" {
  count = local.create_role ? 1 : 0
  name  = "${local.name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  count      = local.create_role ? 1 : 0
  role       = aws_iam_role.lambda_exec[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "backend" {
  function_name    = local.function_name
  filename         = "${path.module}/../backend/lambda.zip"
  source_code_hash = filebase64sha256("${path.module}/../backend/lambda.zip")
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  role             = local.role_arn
  timeout          = 15
  memory_size      = 256

  environment {
    variables = {
      MONGO_URI = var.mongo_uri
    }
  }

  # Create the log group first so it gets 14-day retention + tags.
  depends_on = [aws_cloudwatch_log_group.lambda, aws_iam_role_policy_attachment.lambda_basic_execution]
}

# =====================================================================
# 3. API GATEWAY (HTTP API)
# =====================================================================
resource "aws_apigatewayv2_api" "api" {
  name          = "${local.name}-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    allow_headers = ["*"]
  }
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.api.id
  name        = "$default"
  auto_deploy = true

  # Tier 4: JSON access logs
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.apigw_access.arn
    format = jsonencode({
      requestId          = "$context.requestId"
      ip                 = "$context.identity.sourceIp"
      requestTime        = "$context.requestTime"
      method             = "$context.httpMethod"
      path               = "$context.path"
      route              = "$context.routeKey"
      status             = "$context.status"
      responseLength     = "$context.responseLength"
      integrationStatus  = "$context.integrationStatus"
      integrationLatency = "$context.integrationLatency"
      integrationError   = "$context.integrationErrorMessage"
    })
  }
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.backend.invoke_arn
  payload_format_version = "2.0"
}

# Explicit routes: the Lambda reads pathParameters["id"], which only exists
# with a /notices/{id} route (a catch-all "ANY /{proxy+}" would break delete).
resource "aws_apigatewayv2_route" "routes" {
  for_each = toset([
    "GET /notices",
    "POST /notices",
    "GET /notices/{id}",
    "PUT /notices/{id}",
    "DELETE /notices/{id}",
  ])

  api_id    = aws_apigatewayv2_api.api.id
  route_key = each.value
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.backend.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
}

# =====================================================================
# 4. CLOUDFRONT CDN with ORIGIN ACCESS CONTROL (Tier 3)
# =====================================================================
resource "aws_cloudfront_origin_access_control" "oac" {
  count                             = var.enable_cloudfront ? 1 : 0
  name                              = "${local.name}-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "cdn" {
  count               = var.enable_cloudfront ? 1 : 0
  comment             = "${local.name} frontend"
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  price_class         = "PriceClass_100"

  origin {
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.oac[0].id
    origin_id                = "S3-${aws_s3_bucket.frontend.id}"
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "S3-${aws_s3_bucket.frontend.id}"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true
    cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6" # AWS managed "CachingOptimized"
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# =====================================================================
# 5. OBSERVABILITY (Tier 4, optional): logs, alarms, dashboard, queries
# =====================================================================
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "apigw_access" {
  name              = "/aws/apigateway/${local.name}-access"
  retention_in_days = 14
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${local.name}-lambda-errors"
  alarm_description   = "Lambda function errors > 0 in 5 minutes"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.backend.function_name
  }
}

resource "aws_cloudwatch_metric_alarm" "apigw_5xx" {
  alarm_name          = "${local.name}-apigw-5xx"
  alarm_description   = "API Gateway 5XX responses > 0 in 5 minutes"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "5xx"
  namespace           = "AWS/ApiGateway"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    ApiId = aws_apigatewayv2_api.api.id
  }
}

locals {
  dashboard_widgets = concat(
    [
      jsonencode({
        type = "metric", x = 0, y = 0, width = 12, height = 6
        properties = {
          title  = "Lambda"
          region = var.aws_region
          period = 60
          stat   = "Sum"
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", local.function_name],
            [".", "Errors", ".", "."],
            [".", "Duration", ".", ".", { stat = "p95", yAxis = "right" }],
          ]
        }
      }),
      jsonencode({
        type = "metric", x = 12, y = 0, width = 12, height = 6
        properties = {
          title  = "API Gateway"
          region = var.aws_region
          period = 60
          stat   = "Sum"
          metrics = [
            ["AWS/ApiGateway", "Count", "ApiId", aws_apigatewayv2_api.api.id],
            [".", "4xx", ".", "."],
            [".", "5xx", ".", "."],
            [".", "Latency", ".", ".", { stat = "p95", yAxis = "right" }],
          ]
        }
      }),
    ],
    var.enable_cloudfront ? [
      jsonencode({
        type = "metric", x = 0, y = 6, width = 24, height = 6
        properties = {
          title  = "CloudFront"
          region = "us-east-1"
          period = 300
          stat   = "Sum"
          metrics = [
            ["AWS/CloudFront", "Requests", "DistributionId", aws_cloudfront_distribution.cdn[0].id, "Region", "Global"],
            [".", "4xxErrorRate", ".", ".", ".", ".", { stat = "Average", yAxis = "right" }],
            [".", "5xxErrorRate", ".", ".", ".", ".", { stat = "Average", yAxis = "right" }],
          ]
        }
      }),
    ] : []
  )
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = local.name
  dashboard_body = "{\"widgets\":[${join(",", local.dashboard_widgets)}]}"
}

resource "aws_cloudwatch_query_definition" "lambda_errors" {
  name            = "${local.name}/lambda-errors"
  log_group_names = [aws_cloudwatch_log_group.lambda.name]
  query_string    = <<-EOT
    fields @timestamp, @requestId, @message
    | filter @message like /(?i)(error|exception|task timed out)/
    | sort @timestamp desc
    | limit 50
  EOT
}

resource "aws_cloudwatch_query_definition" "apigw_status" {
  name            = "${local.name}/api-requests-by-status"
  log_group_names = [aws_cloudwatch_log_group.apigw_access.name]
  query_string    = <<-EOT
    fields @timestamp, method, route, status, integrationLatency
    | stats count(*) as requests, avg(integrationLatency) as avgLatencyMs by route, status
    | sort requests desc
  EOT
}
