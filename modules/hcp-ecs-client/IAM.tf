
resource "aws_iam_policy" "hashicups" {
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = var.iam_actions_allow.logging_create_and_put
        Effect   = var.iam_effect.allow
        Resource = ["*"]
      },
      {
        Action = var.iam_actions_allow.elastic_load_balancer
        Effect = var.iam_effect.allow
        Resource = [
          aws_lb.example_client_app.arn
        ]
     },
    {
       Effect   = "Allow"
       Action   = [
            "ssmmessages:CreateControlChannel",
            "ssmmessages:CreateDataChannel",
            "ssmmessages:OpenControlChannel",
            "ssmmessages:OpenDataChannel"
       ]
       Resource = ["*"]
      }]
  })
}

data "aws_caller_identity" "current" {}



  variable "iam_service_principals" {
  type        = map(string)
  description = "Names of the Services Principals this tutorial needs"
  default = {
    ecs_tasks = "ecs-tasks.amazonaws.com"
    ecs       = "ecs.amazonaws.com"
  }
}

variable "iam_role_name" {
  type        = string
  description = "Base name of the IAM role to create in this tutorial"
  default     = "hashicups"
}

variable "iam_effect" {
  type        = map(string)
  description = "Allow or Deny for IAM policies"
  default = {
    allow = "Allow"
    deny  = "Deny"
  }
}

variable "iam_action_type" {
  type        = map(string)
  description = "Actions required for IAM roles in this tutorial"
  default = {
    assume_role = "sts:AssumeRole"
  }
}
variable "iam_actions_allow" {
  type        = map(any)
  description = "What resources an IAM role is accessing in this tutorial"
  default = {
    secrets_manager_get = ["secretsmanager:GetSecretValue"]
    logging_create_and_put = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
    "logs:PutLogEvent"]
    elastic_load_balancer = ["elasticloadbalancing:*"]

  }
}

variable "iam_logs_actions_allow" {
  default = [
    "logs:CreateLogGroup",
    "logs:CreateLogStream",
    "logs:PutLogEvent"
  ]
}