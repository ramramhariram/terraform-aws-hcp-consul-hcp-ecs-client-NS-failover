# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

resource "aws_lb" "ingress" {
  name               = "${local.secret_prefix}-ingress"
  internal           = false
  load_balancer_type = "application"
  security_groups    = var.security_group_id
  subnets            = var.public_subnet_ids
}

resource "aws_lb_target_group" "frontend" {
  name                 = "${local.secret_prefix}-frontend"
  port                 = local.frontend_port
  protocol             = "HTTP"
  vpc_id               = var.vpc_id
  target_type          = "ip"
  deregistration_delay = 10
}

resource "aws_lb_target_group" "public-api" {
  name                 = "${local.secret_prefix}-api"
  port                 = local.public_api_port
  protocol             = "HTTP"
  vpc_id               = var.vpc_id
  target_type          = "ip"
  deregistration_delay = 10
}

resource "aws_lb_listener" "frontend" {
  load_balancer_arn = aws_lb.ingress.arn
  port              = local.lb_port
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }
}

resource "aws_lb_listener_rule" "public-api" {
  listener_arn = aws_lb_listener.frontend.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.public-api.arn
  }

  condition {
    path_pattern {
      values = ["/api", "/api/*"]
    }
  }
}


###LB for fake service



####LB config 

resource "aws_lb" "example_client_app" {
  name               = "example-client-app"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.LB_SG_Alltraffic.id, var.security_group_id]
  subnets            = var.public_subnet_ids
}

resource "aws_lb_target_group" "example_client_app" {
  name                 = "example-client-app"
  port                 = 9090
  protocol             = "HTTP"
  vpc_id               = var.vpc_id
  target_type          = "ip"
  deregistration_delay = 10
  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 10
    timeout             = 30
    interval            = 60
  }
}

resource "aws_lb_listener" "example_client_app" {
  load_balancer_arn = aws_lb.example_client_app.arn
  port              = "9090"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.example_client_app.arn
  }
} 


#all traffic SG for the LB 

resource "aws_security_group" "LB_SG_Alltraffic" {
  name        = "LB_SG_Alltraffic"
  description = "Allow all consul traffic inbound"
  vpc_id      = var.vpc_id
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  #below only for testing
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }
}




