locals {
  # ECS Services 정의
  ecs_services = {
    app-frontend = {
      service_name    = "msa-frontend"
      container_name  = "frontend"
      container_image = "nginx:latest"
      container_port  = 80
      task_cpu        = "256"
      task_memory     = "512"
      desired_count   = 2
      health_check_path = "/"
      environment = [
        {
          name  = "ENVIRONMENT"
          value = "production"
        }
      ]
    }

    app-backend = {
      service_name    = "msa-backend"
      container_name  = "backend"
      container_image = "node:18-alpine"
      container_port  = 3000
      task_cpu        = "512"
      task_memory     = "1024"
      desired_count   = 3
      health_check_path = "/health"
      environment = [
        {
          name  = "ENVIRONMENT"
          value = "production"
        },
        {
          name  = "LOG_LEVEL"
          value = "info"
        }
      ]
    }

    app-api = {
      service_name    = "msa-api"
      container_name  = "api"
      container_image = "python:3.11-slim"
      container_port  = 8000
      task_cpu        = "512"
      task_memory     = "1024"
      desired_count   = 2
      health_check_path = "/api/health"
      environment = [
        {
          name  = "ENVIRONMENT"
          value = "production"
        },
        {
          name  = "DEBUG"
          value = "false"
        }
      ]
    }

    app-worker = {
      service_name    = "msa-worker"
      container_name  = "worker"
      container_image = "worker:latest"
      container_port  = 9000
      task_cpu        = "256"
      task_memory     = "512"
      desired_count   = 1
      health_check_path = "/status"
      environment = [
        {
          name  = "ENVIRONMENT"
          value = "production"
        }
      ]
    }
  }

  tags = merge(
    var.tags,
    {
      ManagedBy = "terraform"
      CreatedAt = timestamp()
    }
  )
}
