output "website_url" {
  description = "Open this in the browser"
  value = var.enable_cloudfront ? "https://${aws_cloudfront_distribution.cdn[0].domain_name}" : "http://${aws_s3_bucket_website_configuration.frontend[0].website_endpoint}"
}

output "api_gateway_url" {
  description = "Base URL of the API -> GitHub secret VITE_API_URL"
  value       = aws_apigatewayv2_api.api.api_endpoint
}

output "s3_bucket_name" {
  description = "Frontend bucket -> GitHub secret S3_BUCKET"
  value       = aws_s3_bucket.frontend.id
}

output "lambda_function_name" {
  description = "-> GitHub secret LAMBDA_FUNCTION_NAME"
  value       = aws_lambda_function.backend.function_name
}

output "cloudfront_distribution_id" {
  description = "-> GitHub secret CF_DISTRIBUTION_ID (Tier 3)"
  value       = var.enable_cloudfront ? aws_cloudfront_distribution.cdn[0].id : null
}

output "cloudfront_domain_name" {
  value = var.enable_cloudfront ? aws_cloudfront_distribution.cdn[0].domain_name : null
}

output "dashboard_name" {
  value = aws_cloudwatch_dashboard.main.dashboard_name
}
