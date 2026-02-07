terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# VPC Module
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.cluster_name}-vpc"
  cidr = var.vpc_cidr

  azs             = data.aws_availability_zones.available.names
  private_subnets = var.private_subnets
  public_subnets  = var.public_subnets

  enable_nat_gateway = true
  single_nat_gateway = true
  enable_vpn_gateway = false

  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = local.tags
}

# ECS Cluster Module
module "ecs" {
  source  = "terraform-aws-modules/ecs/aws"
  version = "~> 5.0"

  cluster_name = var.cluster_name

  # Cluster capacity providers
  cluster_configuration = {
    execute_command_configuration = {
      logging = "OVERRIDE"
    }
  }

  # Default capacity provider strategy
  fargate_capacity_providers = {
    FARGATE = {
      default_capacity_provider_strategy = {
        weight = 50
      }
    }
    FARGATE_SPOT = {
      default_capacity_provider_strategy = {
        weight = 50
      }
    }
  }


  tags = local.tags
}

# ECS Task Definition - For Each
resource "aws_ecs_task_definition" "app" {
  for_each = local.ecs_services

  family                   = each.value.service_name
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = each.value.task_cpu
  memory                   = each.value.task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = each.value.container_name
      image     = each.value.container_image
      cpu       = tonumber(each.value.task_cpu)
      memory    = tonumber(each.value.task_memory)
      essential = true

      portMappings = [
        {
          containerPort = each.value.container_port
          hostPort      = each.value.container_port
          protocol      = "tcp"
        }
      ]

      environment = each.value.environment

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs[each.key].name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  tags = local.tags
}

# ECS Service Module - For Each
module "ecs_service" {
  for_each = local.ecs_services

  source  = "terraform-aws-modules/ecs/aws//modules/service"
  version = "~> 5.0"

  name        = each.value.service_name
  cluster_arn = module.ecs.cluster_arn

  # Task Definition
  task_definition_arn = aws_ecs_task_definition.app[each.key].arn

  # Service properties
  desired_count                      = each.value.desired_count
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  # Network configuration
  network_mode        = "awsvpc"
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [aws_security_group.ecs_service[each.key].id]

  # Load balancer configuration
  load_balancer = {
    service = {
      target_group_arn = aws_lb_target_group.app[each.key].arn
      container_name   = each.value.container_name
      container_port   = each.value.container_port
    }
  }

  # Capacity provider
  capacity_provider_strategy = {
    FARGATE_SPOT = {
      capacity_provider = "FARGATE_SPOT"
      weight            = 100
      base              = 1
    }
  }

  tags = local.tags
}

# Application Load Balancer
resource "aws_lb" "app" {
  name            = "${var.cluster_name}-alb"
  internal        = false
  load_balancer_type = "application"
  security_groups = [aws_security_group.alb.id]
  subnets         = module.vpc.public_subnets

  tags = local.tags
}

# Target Group - For Each
resource "aws_lb_target_group" "app" {
  for_each = local.ecs_services

  name        = "${each.value.service_name}-tg"
  port        = each.value.container_port
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    interval            = 30
    path                = each.value.health_check_path
    matcher             = "200"
  }

  tags = local.tags
}

# ALB Listener
resource "aws_lb_listener" "app" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app[keys(local.ecs_services)[0]].arn
  }
}

# ALB Listener Rules - For Each
resource "aws_lb_listener_rule" "app" {
  for_each = local.ecs_services

  listener_arn = aws_lb_listener.app.arn
  priority     = index(keys(local.ecs_services), each.key) + 1

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app[each.key].arn
  }

  condition {
    path_pattern {
      values = ["/${each.value.service_name}*", "/${each.key}*"]
    }
  }
}

# Security Group for ALB
resource "aws_security_group" "alb" {
  name        = "${var.cluster_name}-alb-sg"
  description = "Security group for ALB"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.tags
}

# Security Group for ECS Service - For Each
resource "aws_security_group" "ecs_service" {
  for_each = local.ecs_services

  name        = "${var.cluster_name}-${each.key}-sg"
  description = "Security group for ${each.value.service_name}"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port       = each.value.container_port
    to_port         = each.value.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.tags
}

# CloudWatch Log Group - For Each
resource "aws_cloudwatch_log_group" "ecs" {
  for_each = local.ecs_services

  name              = "/ecs/${each.value.service_name}"
  retention_in_days = var.log_retention_days

  tags = local.tags
}

# IAM Role for ECS Task Execution
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "${var.cluster_name}-task-execution-role"

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

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# IAM Role for ECS Task
resource "aws_iam_role" "ecs_task_role" {
  name = "${var.cluster_name}-task-role"

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

  tags = local.tags
}

# Data source for availability zones
data "aws_availability_zones" "available" {
  state = "available"
}
