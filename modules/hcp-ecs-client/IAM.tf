resource "aws_iam_role" "hashicups" {
  #for_each = { for cluster in var.ecs_ap_globals.ecs_clusters : cluster.name => cluster }
  name     = var.name
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = var.iam_effect.allow
        Principal = {
          Service = var.iam_service_principals.ecs_tasks
        }
        Action = var.iam_action_type.assume_role
      },
      {
        Effect = var.iam_effect.allow
        Principal = {
          "AWS" = [local.ecs_service_role]
        }
        Action = var.iam_action_type.assume_role
      },
      {
        Effect = var.iam_effect.allow
        Principal = {
          Service = var.iam_service_principals.ecs
        }
        Action = var.iam_action_type.assume_role
      },
    ]
  })
}

resource "aws_iam_policy" "hashicups" {
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = var.iam_actions_allow.secrets_manager_get
        Effect = var.iam_effect.allow
        Resource = [
          aws_secretsmanager_secret.gossip_key.arn,
          aws_secretsmanager_secret.bootstrap_token.arn,
          aws_secretsmanager_secret.consul_ca_cert.arn,
          aws_lb.example_client_app.arn
        ]
      },
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

resource "aws_iam_role_policy_attachment" "hashicups" {
  #for_each   = aws_iam_role.hashicups
  policy_arn = aws_iam_policy.hashicups.arn
  role       = aws_iam_role.hashicups.name
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