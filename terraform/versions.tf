terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  # Workshop tagging rule: every resource gets these tags,
  # otherwise the nightly cleanup script deletes it.
  default_tags {
    tags = {
      workshop   = "full-stack"
      autodelete = "true"
      date       = var.created_date
      student    = var.student_name
      project    = "notice-board"
    }
  }
}
