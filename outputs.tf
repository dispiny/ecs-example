output "cluster_name" {
  description = "ECS cluster name"
  value       = module.ecs.cluster_name
}

output "cluster_arn" {
  description = "ECS cluster ARN"
  value       = module.ecs.cluster_arn
}

output "services" {
  description = "ECS services information"
  value = {
    for key, service in module.ecs_service : key => {
      name = service.name
      arn  = service.arn
    }
  }
}

output "task_definitions" {
  description = "ECS task definitions ARNs"
  value = {
    for key, task in aws_ecs_task_definition.app : key => {
      arn  = task.arn
      name = task.family
    }
  }
}

output "target_groups" {
  description = "Target groups information"
  value = {
    for key, tg in aws_lb_target_group.app : key => {
      arn  = tg.arn
      name = tg.name
    }
  }
}

output "load_balancer_dns_name" {
  description = "DNS name of the load balancer"
  value       = aws_lb.app.dns_name
}

output "load_balancer_arn" {
  description = "ARN of the load balancer"
  value       = aws_lb.app.arn
}

output "cloudwatch_log_groups" {
  description = "CloudWatch log group names for ECS tasks"
  value = {
    for key, lg in aws_cloudwatch_log_group.ecs : key => lg.name
  }
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "task_execution_role_arn" {
  description = "ECS task execution role ARN"
  value       = aws_iam_role.ecs_task_execution_role.arn
}

output "task_role_arn" {
  description = "ECS task role ARN"
  value       = aws_iam_role.ecs_task_role.arn
}

output "security_groups" {
  description = "Security groups for each service"
  value = {
    for key, sg in aws_security_group.ecs_service : key => {
      id   = sg.id
      name = sg.name
    }
  }
}
