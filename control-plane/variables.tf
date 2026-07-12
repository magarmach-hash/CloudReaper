variable "aws_region" {
  description = "AWS region for all control-plane resources"
  type        = string
  default     = "us-east-1"
}

variable "github_owner" {
  description = "GitHub repository owner (user or org)"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
}

variable "github_secret_arn" {
  description = "ARN of the Secrets Manager secret containing the GitHub PAT"
  type        = string
}

variable "scan_interval" {
  description = "EventBridge schedule expression for how often Lambda runs"
  type        = string
  default     = "rate(5 minutes)"
}

variable "log_retention_days" {
  description = "CloudWatch log retention for Lambda logs"
  type        = number
  default     = 14
}
