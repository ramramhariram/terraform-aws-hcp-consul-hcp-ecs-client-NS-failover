# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

module "acl-controller" {
  source  = "hashicorp/consul-ecs/aws//modules/acl-controller"
  version = "0.6.0"

  log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = aws_cloudwatch_log_group.log_group.name
      awslogs-region        = var.region
      awslogs-stream-prefix = "consul-acl-controller-hcp"
    }
  }
  consul_server_http_addr           = var.consul_url
  consul_bootstrap_token_secret_arn = aws_secretsmanager_secret.bootstrap_token.arn
  #consul_server_ca_cert_arn         = aws_secretsmanager_secret.ca_cert.arn #Do not configure for HCP
  ecs_cluster_arn                   = aws_ecs_cluster.clients.arn
  region                            = var.region
  subnets                           = var.private_subnet_ids_az1
  security_groups = [var.security_group_id]
  name_prefix = local.secret_prefix
  consul_partitions_enabled = true 
  consul_partition = "default"
}
#adding a second acl_controller for failover 


module "acl-controller2" {
  source  = "hashicorp/consul-ecs/aws//modules/acl-controller"
  version = "0.6.0"

  log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = aws_cloudwatch_log_group.log_group.name
      awslogs-region        = var.region
      awslogs-stream-prefix = "consul-acl-controller-hcp-2"
    }
  }
  consul_server_http_addr           = var.consul_url
  consul_bootstrap_token_secret_arn = aws_secretsmanager_secret.bootstrap_token.arn
  #consul_server_ca_cert_arn         = aws_secretsmanager_secret.ca_cert.arn #Do not configure for HCP
  ecs_cluster_arn                   = aws_ecs_cluster.clients2.arn
  region                            = var.region
  subnets                           = var.private_subnet_ids_az2
  security_groups = [var.security_group_id]
  name_prefix = "${local.secret_prefix}-2"
  consul_partitions_enabled = true 
  consul_partition = "default"
}


resource "aws_iam_role" "frontend-task-role" {
  name = "frontend_${local.scope}_task_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role" "frontend-execution-role" {
  name = "frontend_${local.scope}_execution_role"
  path = "/ecs/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

module "frontend" {
  source  = "hashicorp/consul-ecs/aws//modules/mesh-task"
  version = "~> 0.6.0"

  family         = "frontend"
  task_role      = aws_iam_role.frontend-task-role
  execution_role = aws_iam_role.frontend-execution-role
  container_definitions = [
    {
      name      = "frontend"
      image     = "hashicorpdemoapp/frontend:v1.0.2"
      essential = true
      portMappings = [
        {
          containerPort = local.frontend_port
          hostPort      = local.frontend_port
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "NEXT_PUBLIC_PUBLIC_API_URL"
          value = "/"
        }
      ]

      cpu         = 0
      mountPoints = []
      volumesFrom = []

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.log_group.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "frontend"
        }
      }
    }
  ]

  log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = aws_cloudwatch_log_group.log_group.name
      awslogs-region        = var.region
      awslogs-stream-prefix = "frontend"
    }
  }

  port = local.frontend_port

  retry_join        = var.client_retry_join
  consul_datacenter = var.datacenter
  consul_image      = "public.ecr.aws/hashicorp/consul-enterprise:${var.consul_version}-ent"
  consul_partition               = "default"
  consul_namespace               = "az1"
  tls                       = true
  consul_server_ca_cert_arn = aws_secretsmanager_secret.ca_cert.arn
  gossip_key_secret_arn     = aws_secretsmanager_secret.gossip_key.arn
  consul_http_addr               = var.consul_url
  #consul_https_ca_cert_arn       = aws_secretsmanager_secret.ca_cert.arn #Do not configure for HCP
  acls                           = true
}

resource "aws_ecs_service" "frontend" {
  name            = "frontend"
  cluster         = aws_ecs_cluster.clients.arn
  task_definition = module.frontend.task_definition_arn
  desired_count   = 1

  network_configuration {
    subnets         = var.private_subnet_ids_az1
    security_groups = [var.security_group_id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.frontend.arn
    container_name   = "frontend"
    container_port   = local.frontend_port
  }

  launch_type            = "FARGATE"
  propagate_tags         = "TASK_DEFINITION"
  enable_execute_command = true
}

resource "aws_iam_role" "public-api-task-role" {
  name = "public_api_${local.scope}_task_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role" "public-api-execution-role" {
  name = "public_api_${local.scope}_execution_role"
  path = "/ecs/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

module "public-api" {
  source  = "hashicorp/consul-ecs/aws//modules/mesh-task"
  version = "~> 0.6.0"

  family         = "public-api"
  task_role      = aws_iam_role.public-api-task-role
  execution_role = aws_iam_role.public-api-execution-role
  container_definitions = [
    {
      name      = "public-api"
      image     = "hashicorpdemoapp/public-api:v0.0.6"
      essential = true
      portMappings = [
        {
          containerPort = local.public_api_port
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "BIND_ADDRESS",
          value = ":${local.public_api_port}"
        },
        {
          name  = "PRODUCT_API_URI"
          value = "http://localhost:${local.product_api_port}"
        },
        {
          name  = "PAYMENT_API_URI"
          value = "http://localhost:${local.payment_api_port}"
        }
      ]

      cpu         = 0
      mountPoints = []
      volumesFrom = []

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.log_group.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "public-api"
        }
      }
    }
  ]

  upstreams = [
    {
      destinationName = "product-api"
      localBindPort   = local.product_api_port
    },
    {
      destinationName = "payment-api"
      localBindPort   = local.payment_api_port
    }
  ]


  log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = aws_cloudwatch_log_group.log_group.name
      awslogs-region        = var.region
      awslogs-stream-prefix = "public-api"
    }
  }

  port = local.public_api_port

  retry_join        = var.client_retry_join
  consul_datacenter = var.datacenter
  consul_image      = "public.ecr.aws/hashicorp/consul-enterprise:${var.consul_version}-ent"
  consul_partition               = "default"
  consul_namespace               = "az1"
  tls                       = true
  consul_server_ca_cert_arn = aws_secretsmanager_secret.ca_cert.arn
  gossip_key_secret_arn     = aws_secretsmanager_secret.gossip_key.arn
  consul_http_addr               = var.consul_url
 #consul_https_ca_cert_arn       = aws_secretsmanager_secret.ca_cert.arn #Do not configure for HCP
  acls                           = true
}

resource "aws_ecs_service" "public-api" {
  name            = "public-api"
  cluster         = aws_ecs_cluster.clients.arn
  task_definition = module.public-api.task_definition_arn
  desired_count   = 1

  network_configuration {
    subnets         = var.private_subnet_ids_az1
    security_groups = [var.security_group_id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.public-api.arn
    container_name   = "public-api"
    container_port   = local.public_api_port
  }

  launch_type            = "FARGATE"
  propagate_tags         = "TASK_DEFINITION"
  enable_execute_command = true
}

resource "aws_iam_role" "payment-api-task-role" {
  name = "payment_api_${local.scope}_task_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role" "payment-api-execution-role" {
  name = "payment_api_${local.scope}_execution_role"
  path = "/ecs/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

module "payment-api" {
  source  = "hashicorp/consul-ecs/aws//modules/mesh-task"
  version = "~> 0.6.0"

  family         = "payment-api"
  task_role      = aws_iam_role.payment-api-task-role
  execution_role = aws_iam_role.payment-api-execution-role
  container_definitions = [
    {
      name      = "payment-api"
      image     = "hashicorpdemoapp/payments:v0.0.16"
      essential = true
      portMappings = [
        {
          containerPort = local.payment_api_port
          protocol      = "tcp"
        }
      ]

      cpu         = 0
      mountPoints = []
      volumesFrom = []

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.log_group.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "payment-api"
        }
      }
    }
  ]

  log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = aws_cloudwatch_log_group.log_group.name
      awslogs-region        = var.region
      awslogs-stream-prefix = "payment-api"
    }
  }

  port = local.payment_api_port

  
  retry_join        = var.client_retry_join
  consul_datacenter = var.datacenter
  consul_image      = "public.ecr.aws/hashicorp/consul-enterprise:${var.consul_version}-ent"
  consul_partition               = "default"
  consul_namespace               = "az1"
  tls                       = true
  consul_server_ca_cert_arn = aws_secretsmanager_secret.ca_cert.arn
  gossip_key_secret_arn     = aws_secretsmanager_secret.gossip_key.arn
  consul_http_addr               = var.consul_url
  #consul_https_ca_cert_arn       = aws_secretsmanager_secret.ca_cert.arn #Do not configure for HCP
  acls                           = true
}

resource "aws_ecs_service" "payment-api" {
  name            = "payment-api"
  cluster         = aws_ecs_cluster.clients.arn
  task_definition = module.payment-api.task_definition_arn
  desired_count   = 1

  network_configuration {
    subnets         = var.private_subnet_ids_az1
    security_groups = [var.security_group_id]
  }

  launch_type            = "FARGATE"
  propagate_tags         = "TASK_DEFINITION"
  enable_execute_command = true
}

resource "aws_iam_role" "product-api-task-role" {
  name = "product_api_${local.scope}_task_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role" "product-api-execution-role" {
  name = "product_api_${local.scope}_execution_role"
  path = "/ecs/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

module "product-api" {
  source  = "hashicorp/consul-ecs/aws//modules/mesh-task"
  version = "~> 0.6.0"

  family         = "product-api"
  task_role      = aws_iam_role.product-api-task-role
  execution_role = aws_iam_role.product-api-execution-role
  container_definitions = [
    {
      name      = "product-api"
      image     = "hashicorpdemoapp/product-api:v0.0.20"
      essential = true
      portMappings = [
        {
          containerPort = local.product_api_port
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "DB_CONNECTION"
          value = "host=localhost port=${local.product_db_port} user=postgres password=password dbname=products sslmode=disable"
        },
        {
          name  = "BIND_ADDRESS"
          value = "localhost:${local.product_api_port}"
        },
      ]
      cpu         = 0
      mountPoints = []
      volumesFrom = []

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.log_group.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "product-api"
        }
      }
    }
  ]

  upstreams = [
    {
      destinationName = "product-db"
      localBindPort   = local.product_db_port
    }
  ]

  log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = aws_cloudwatch_log_group.log_group.name
      awslogs-region        = var.region
      awslogs-stream-prefix = "product-api"
    }
  }

  port = local.product_api_port

  
  retry_join        = var.client_retry_join
  consul_datacenter = var.datacenter
  consul_image      = "public.ecr.aws/hashicorp/consul-enterprise:${var.consul_version}-ent"
  consul_partition               = "default"
  consul_namespace               = "az1"
  tls                       = true
  consul_server_ca_cert_arn = aws_secretsmanager_secret.ca_cert.arn
  gossip_key_secret_arn     = aws_secretsmanager_secret.gossip_key.arn
  consul_http_addr               = var.consul_url
  #consul_https_ca_cert_arn       = aws_secretsmanager_secret.ca_cert.arn #Do not configure for HCP
  acls                           = true
}

resource "aws_ecs_service" "product-api" {
  name            = "product-api"
  cluster         = aws_ecs_cluster.clients.arn
  task_definition = module.product-api.task_definition_arn
  desired_count   = 1

  network_configuration {
    subnets         = var.private_subnet_ids_az1
    security_groups = [var.security_group_id]
  }

  launch_type            = "FARGATE"
  propagate_tags         = "TASK_DEFINITION"
  enable_execute_command = true
}

resource "aws_iam_role" "product-db-task-role" {
  name = "product_db_${local.scope}_task_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role" "product-db-execution-role" {
  name = "product_db_${local.scope}_execution_role"
  path = "/ecs/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

module "product-db" {
  source  = "hashicorp/consul-ecs/aws//modules/mesh-task"
  version = "~> 0.6.0"

  family         = "product-db"
  task_role      = aws_iam_role.product-db-task-role
  execution_role = aws_iam_role.product-db-execution-role
  container_definitions = [
    {
      name      = "product-db"
      image     = "hashicorpdemoapp/product-api-db:v0.0.20"
      essential = true
      portMappings = [
        {
          containerPort = local.product_db_port
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "POSTGRES_DB"
          value = "products"
        },
        {
          name  = "POSTGRES_USER"
          value = "postgres"
        },
        {
          name  = "POSTGRES_PASSWORD"
          value = "password"
        },
      ]
      cpu         = 0
      mountPoints = []
      volumesFrom = []

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.log_group.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "product-db"
        }
      }
    }
  ]

  log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = aws_cloudwatch_log_group.log_group.name
      awslogs-region        = var.region
      awslogs-stream-prefix = "product-db"
    }
  }

  port = local.product_db_port

  
  retry_join        = var.client_retry_join
  consul_datacenter = var.datacenter
  consul_image      = "public.ecr.aws/hashicorp/consul-enterprise:${var.consul_version}-ent"
  consul_partition               = "default"
  consul_namespace               = "az1"
  tls                       = true
  consul_server_ca_cert_arn = aws_secretsmanager_secret.ca_cert.arn
  gossip_key_secret_arn     = aws_secretsmanager_secret.gossip_key.arn
  consul_http_addr               = var.consul_url
  #consul_https_ca_cert_arn       = aws_secretsmanager_secret.ca_cert.arn #Do not configure for HCP
  acls                           = true
}

resource "aws_ecs_service" "product-db" {
  name            = "product-db"
  cluster         = aws_ecs_cluster.clients.arn
  task_definition = module.product-db.task_definition_arn
  desired_count   = 1

  network_configuration {
    subnets         = var.private_subnet_ids_az1
    security_groups = [var.security_group_id]
  }

  launch_type            = "FARGATE"
  propagate_tags         = "TASK_DEFINITION"
  enable_execute_command = true
}


#creating duplicate upstreams - product-db, product-api, payments-api



resource "aws_iam_role" "payment-api-task-role2" {
  name = "payment_api_${local.scope}_task_role2"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role" "payment-api-execution-role2" {
  name = "payment_api_${local.scope}_execution_role2"
  path = "/ecs/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

module "payment-api2" {
  source  = "hashicorp/consul-ecs/aws//modules/mesh-task"
  version = "~> 0.6.0"

  family         = "payment-api2"
  task_role      = aws_iam_role.payment-api-task-role2
  execution_role = aws_iam_role.payment-api-execution-role2
  container_definitions = [
    {
      name      = "payment-api"
      image     = "hashicorpdemoapp/payments:v0.0.16"
      essential = true
      portMappings = [
        {
          containerPort = local.payment_api_port
          protocol      = "tcp"
        }
      ]

      cpu         = 0
      mountPoints = []
      volumesFrom = []

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.log_group.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "payment-api2"
        }
      }
    }
  ]

  log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = aws_cloudwatch_log_group.log_group.name
      awslogs-region        = var.region
      awslogs-stream-prefix = "payment-api2"
    }
  }

  port = local.payment_api_port

  
  retry_join        = var.client_retry_join
  consul_service_name = "payment-api"
  consul_datacenter = var.datacenter
  consul_image      = "public.ecr.aws/hashicorp/consul-enterprise:${var.consul_version}-ent"
  consul_partition               = "default"
  consul_namespace               = "az2"
  tls                       = true
  consul_server_ca_cert_arn = aws_secretsmanager_secret.ca_cert.arn
  gossip_key_secret_arn     = aws_secretsmanager_secret.gossip_key.arn
  consul_http_addr               = var.consul_url
  #consul_https_ca_cert_arn       = aws_secretsmanager_secret.ca_cert.arn #Do not configure for HCP
  acls                           = true
}

resource "aws_ecs_service" "payment-api2" {
  name            = "payment-api2"
  cluster         = aws_ecs_cluster.clients2.arn
  task_definition = module.payment-api2.task_definition_arn
  desired_count   = 1

  network_configuration {
    subnets         = var.private_subnet_ids_az2
    security_groups = [var.security_group_id]
  }

  launch_type            = "FARGATE"
  propagate_tags         = "TASK_DEFINITION"
  enable_execute_command = true
}

resource "aws_iam_role" "product-api-task-role2" {
  name = "product_api_${local.scope}_task_role2"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role" "product-api-execution-role2" {
  name = "product_api_${local.scope}_execution_role2"
  path = "/ecs/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

module "product-api2" {
  source  = "hashicorp/consul-ecs/aws//modules/mesh-task"
  version = "~> 0.6.0"

  family         = "product-api2"
  task_role      = aws_iam_role.product-api-task-role2
  execution_role = aws_iam_role.product-api-execution-role2
  container_definitions = [
    {
      name      = "product-api"
      image     = "hashicorpdemoapp/product-api:v0.0.20"
      essential = true
      portMappings = [
        {
          containerPort = local.product_api_port
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "DB_CONNECTION"
          value = "host=localhost port=${local.product_db_port} user=postgres password=password dbname=products sslmode=disable"
        },
        {
          name  = "BIND_ADDRESS"
          value = "localhost:${local.product_api_port}"
        },
      ]
      cpu         = 0
      mountPoints = []
      volumesFrom = []

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.log_group.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "product-api2"
        }
      }
    }
  ]

  upstreams = [
    {
      destinationName = "product-db"
      localBindPort   = local.product_db_port
    }
  ]

  log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = aws_cloudwatch_log_group.log_group.name
      awslogs-region        = var.region
      awslogs-stream-prefix = "product-api2"
    }
  }

  port = local.product_api_port

  
  retry_join        = var.client_retry_join
  consul_datacenter = var.datacenter
  consul_service_name = "product-api"
  consul_image      = "public.ecr.aws/hashicorp/consul-enterprise:${var.consul_version}-ent"
  consul_partition               = "default"
  consul_namespace               = "az2"
  tls                       = true
  consul_server_ca_cert_arn = aws_secretsmanager_secret.ca_cert.arn
  gossip_key_secret_arn     = aws_secretsmanager_secret.gossip_key.arn
  consul_http_addr               = var.consul_url
  #consul_https_ca_cert_arn       = aws_secretsmanager_secret.ca_cert.arn #Do not configure for HCP
  acls                           = true
}

resource "aws_ecs_service" "product-api2" {
  name            = "product-api2"
  cluster         = aws_ecs_cluster.clients2.arn
  task_definition = module.product-api2.task_definition_arn
  desired_count   = 1

  network_configuration {
    subnets         = var.private_subnet_ids_az2
    security_groups = [var.security_group_id]
  }

  launch_type            = "FARGATE"
  propagate_tags         = "TASK_DEFINITION"
  enable_execute_command = true
}

resource "aws_iam_role" "product-db-task-role2" {
  name = "product_db_${local.scope}_task_role2"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role" "product-db-execution-role2" {
  name = "product_db_${local.scope}_execution_role2"
  path = "/ecs/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

module "product-db2" {
  source  = "hashicorp/consul-ecs/aws//modules/mesh-task"
  version = "~> 0.6.0"

  family         = "product-db2"
  task_role      = aws_iam_role.product-db-task-role2
  execution_role = aws_iam_role.product-db-execution-role2
  container_definitions = [
    {
      name      = "product-db"
      image     = "hashicorpdemoapp/product-api-db:v0.0.20"
      essential = true
      portMappings = [
        {
          containerPort = local.product_db_port
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "POSTGRES_DB"
          value = "products"
        },
        {
          name  = "POSTGRES_USER"
          value = "postgres"
        },
        {
          name  = "POSTGRES_PASSWORD"
          value = "password"
        },
      ]
      cpu         = 0
      mountPoints = []
      volumesFrom = []

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.log_group.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "product-db"
        }
      }
    }
  ]

  log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = aws_cloudwatch_log_group.log_group.name
      awslogs-region        = var.region
      awslogs-stream-prefix = "product-db"
    }
  }

  port = local.product_db_port

  
  retry_join        = var.client_retry_join
  consul_datacenter = var.datacenter
  consul_service_name = "product-db"
  consul_image      = "public.ecr.aws/hashicorp/consul-enterprise:${var.consul_version}-ent"
  consul_partition               = "default"
  consul_namespace               = "az2"
  tls                       = true
  consul_server_ca_cert_arn = aws_secretsmanager_secret.ca_cert.arn
  gossip_key_secret_arn     = aws_secretsmanager_secret.gossip_key.arn
  consul_http_addr               = var.consul_url
  #consul_https_ca_cert_arn       = aws_secretsmanager_secret.ca_cert.arn #Do not configure for HCP
  acls                           = true
}

resource "aws_ecs_service" "product-db2" {
  name            = "product-db2"
  cluster         = aws_ecs_cluster.clients2.arn
  task_definition = module.product-db2.task_definition_arn
  desired_count   = 1

  network_configuration {
    subnets         = var.private_subnet_ids_az2
    security_groups = [var.security_group_id]
  }

  launch_type            = "FARGATE"
  propagate_tags         = "TASK_DEFINITION"
  enable_execute_command = true
}


#####FAKE_Services

######modules ---
#example: https://developer.hashicorp.com/consul/docs/ecs/terraform/secure-configuration#acl-controller
module "acl_controller3" {
  source  = "hashicorp/consul-ecs/aws//modules/acl-controller"
  version = "0.6.0"

  log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = aws_cloudwatch_log_group.log_group.name
      awslogs-region        = var.region
      awslogs-stream-prefix = "consul-acl-controller-fakeservice"
    }
  }
  consul_server_http_addr           = var.consul_url
  consul_bootstrap_token_secret_arn = aws_secretsmanager_secret.bootstrap_token.arn
  #consul_server_ca_cert_arn         = aws_secretsmanager_secret.ca_cert.arn #Do not configure for HCP
  ecs_cluster_arn                   = aws_ecs_cluster.clients3.arn
  region                            = var.region
  subnets                           = var.private_subnet_ids_az1
  security_groups = [var.security_group_id]
  name_prefix = "${local.secret_prefix}-3"
  consul_partitions_enabled = true 
  consul_partition = "default"
}

module "acl_controller4" {
  source  = "hashicorp/consul-ecs/aws//modules/acl-controller"
  version = "0.6.0"

  log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = aws_cloudwatch_log_group.log_group.name
      awslogs-region        = var.region
      awslogs-stream-prefix = "consul-acl-controller-fakeservice2"
    }
  }
  consul_server_http_addr           = var.consul_url
  consul_bootstrap_token_secret_arn = aws_secretsmanager_secret.bootstrap_token.arn
  #consul_server_ca_cert_arn         = aws_secretsmanager_secret.ca_cert.arn #Do not configure for HCP
  ecs_cluster_arn                   = aws_ecs_cluster.clients4.arn
  region                            = var.region
  subnets                           = var.private_subnet_ids_az2
  security_groups = [var.security_group_id]
  name_prefix = "${local.secret_prefix}-4"
  consul_partitions_enabled = true 
  consul_partition = "default"
}


module "example_client_app" {
  source  = "hashicorp/consul-ecs/aws//modules/mesh-task"
  version = "0.6.0"

  family            = "example-client-app"
  port              = "9090"
  #log_configuration = local.example_client_app_log_config
  log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = aws_cloudwatch_log_group.log_group.name
      awslogs-region        = var.region
      awslogs-stream-prefix = "consul-disney-client"
    }
  }
  container_definitions = [{
    name             = "example-client-app"
    image            = "ghcr.io/lkysow/fake-service:v0.21.0"
    essential        = true
    #logConfiguration = local.example_client_app_log_config
  log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = aws_cloudwatch_log_group.log_group.name
      awslogs-region        = var.region
      awslogs-stream-prefix = "consul-disney-client"
    }
  }
    environment = [
      {
        name  = "NAME"
        value = "example-client-app"
      },
      {
        name  = "UPSTREAM_URIS"
        value = "http://localhost:1234"
      }
    ]
    portMappings = [
      {
        containerPort = 9090
        hostPort      = 9090
        protocol      = "tcp"
      }
    ]
    cpu         = 0
    mountPoints = []
    volumesFrom = []
  }]
  upstreams = [
    {
      destinationName = "example-server-app"
      localBindPort  = 1234
    }
  ]
  
  retry_join        = var.client_retry_join
  consul_datacenter = var.datacenter
  consul_image      = "public.ecr.aws/hashicorp/consul-enterprise:${var.consul_version}-ent"
  consul_partition               = "default"
  consul_namespace               = "az1"
  tls                       = true
  consul_server_ca_cert_arn = aws_secretsmanager_secret.ca_cert.arn
  gossip_key_secret_arn     = aws_secretsmanager_secret.gossip_key.arn
  consul_http_addr               = var.consul_url
  #consul_https_ca_cert_arn       = aws_secretsmanager_secret.ca_cert.arn #Do not configure for HCP
  acls                           = true
  additional_task_role_policies  = [aws_iam_policy.hashicups.arn]
  additional_execution_role_policies = [aws_iam_policy.hashicups.arn]
}

module "example_server_app" {
  source  = "hashicorp/consul-ecs/aws//modules/mesh-task"
  version = "0.6.0"

  family            = "example-server-app"
  port              = "9090"
  #log_configuration = local.example_server_app_log_config
  log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = aws_cloudwatch_log_group.log_group.name
      awslogs-region        = var.region
      awslogs-stream-prefix = "consul-disney-server"
    }
  }
  container_definitions = [{
    name             = "example-server-app"
    image            = "ghcr.io/lkysow/fake-service:v0.21.0"
    essential        = true
   #logConfiguration = local.example_server_app_log_config
    log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = aws_cloudwatch_log_group.log_group.name
      awslogs-region        = var.region
      awslogs-stream-prefix = "consul-disney-server"
    }
  }
    environment = [
      {
        name  = "NAME"
        value = "example-server-app"
      }
    ]
  }]
  retry_join        = var.client_retry_join
  consul_datacenter = var.datacenter
  consul_image      = "public.ecr.aws/hashicorp/consul-enterprise:${var.consul_version}-ent"
  consul_partition               = "default"
  consul_namespace               = "az1"
  tls                       = true
  consul_server_ca_cert_arn = aws_secretsmanager_secret.ca_cert.arn
  gossip_key_secret_arn     = aws_secretsmanager_secret.gossip_key.arn
  consul_http_addr               = var.consul_url
  #consul_https_ca_cert_arn       = aws_secretsmanager_secret.ca_cert.arn #Do not configure for HCP
  acls                           = true
  additional_task_role_policies  = [aws_iam_policy.hashicups.arn]
  additional_execution_role_policies = [aws_iam_policy.hashicups.arn]
}


module "example_server_app2" {
  source  = "hashicorp/consul-ecs/aws//modules/mesh-task"
  version = "0.6.0"

  family            = "example-server-app2"
  port              = "9090"
  #log_configuration = local.example_server_app_log_config
  log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = aws_cloudwatch_log_group.log_group.name
      awslogs-region        = var.region
      awslogs-stream-prefix = "consul-disney-server2"
    }
  }
  container_definitions = [{
    name             = "example-server-app"
    image            = "ghcr.io/lkysow/fake-service:v0.21.0"
    essential        = true
   #logConfiguration = local.example_server_app_log_config
    log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = aws_cloudwatch_log_group.log_group.name
      awslogs-region        = var.region
      awslogs-stream-prefix = "consul-disney-server2"
    }
  }
    environment = [
      {
        name  = "NAME"
        value = "example-server-app"
      }
    ]
  }]
  retry_join        = var.client_retry_join
  consul_datacenter = var.datacenter
  consul_image      = "public.ecr.aws/hashicorp/consul-enterprise:${var.consul_version}-ent"
  consul_partition               = "default"
  consul_namespace               = "az2"
  consul_service_name = "example-server-app"
  tls                       = true
  consul_server_ca_cert_arn = aws_secretsmanager_secret.ca_cert.arn
  gossip_key_secret_arn     = aws_secretsmanager_secret.gossip_key.arn
  consul_http_addr               = var.consul_url
  #consul_https_ca_cert_arn       = aws_secretsmanager_secret.ca_cert.arn #Do not configure for HCP
  acls                           = true
  additional_task_role_policies  = [aws_iam_policy.hashicups.arn]
  additional_execution_role_policies = [aws_iam_policy.hashicups.arn]
}


resource "aws_ecs_service" "example_client_app" {
  name            = "example-client-app"
  cluster         = aws_ecs_cluster.clients3.arn
  task_definition = module.example_client_app.task_definition_arn
  desired_count   = 1
  network_configuration {
    subnets         = var.private_subnet_ids_az1
    security_groups = [var.security_group_id]
  }
  launch_type    = "FARGATE"
  propagate_tags = "TASK_DEFINITION"
  load_balancer {
    target_group_arn = aws_lb_target_group.example_client_app.arn
    container_name   = "example-client-app"
    container_port   = 9090
  }
  enable_execute_command = true
}

# The server app is part of the service mesh. It's called
# by the client app.
resource "aws_ecs_service" "example_server_app" {
  name            = "example-server-app"
  cluster         = aws_ecs_cluster.clients3.arn
  task_definition = module.example_server_app.task_definition_arn
  desired_count   = 1
  network_configuration {
    subnets         = var.private_subnet_ids_az1
    security_groups = [var.security_group_id]
  }
  launch_type            = "FARGATE"
  propagate_tags         = "TASK_DEFINITION"
  enable_execute_command = true
}

# The server app is part of the service mesh. It's called
# by the client app.
resource "aws_ecs_service" "example_server_app2" {
  name            = "example-server-app"
  cluster         = aws_ecs_cluster.clients4.arn
  task_definition = module.example_server_app2.task_definition_arn
  desired_count   = 1
  network_configuration {
    subnets         = var.private_subnet_ids_az2
    security_groups = [var.security_group_id]
  }
  launch_type            = "FARGATE"
  propagate_tags         = "TASK_DEFINITION"
  enable_execute_command = true
}


