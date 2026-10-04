variable "student_name" {
  type        = string
  description = "Your name, used as the prefix for every resource (lowercase, dashes)"
  default     = "rohan-krishna-bandla"
}

variable "aws_region" {
  type        = string
  description = "AWS region (the class account only allows us-east-1)"
  default     = "us-east-1"
}

variable "created_date" {
  type        = string
  description = "Value for the required 'date' tag, format dd-mmm-yyyy"
  default     = "28-Sep-2026"
}

variable "mongo_uri" {
  type        = string
  description = "MongoDB connection string (MongoDB on EC2 or Atlas). Keep it in terraform.tfvars, never commit it."
  sensitive   = true
}

variable "lambda_role_arn" {
  type        = string
  description = <<-EOT
    ARN of an existing Lambda execution role.
    Class AWS account: students cannot create IAM roles, so paste the shared
    quicklabs-...-lambda-exec role ARN here. Own AWS account: leave empty and
    Terraform creates a role for you.
  EOT
  default     = ""
}

variable "enable_cloudfront" {
  type        = bool
  description = <<-EOT
    false = Tier 1: public S3 static website (http://...s3-website...).
    true  = Tier 3: CloudFront (HTTPS) in front of a private S3 bucket.
  EOT
  default     = true
}
