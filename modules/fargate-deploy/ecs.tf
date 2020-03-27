provider "aws" {
  region     = var.aws_region
}

### Peering cluster VPC with the master VPC 
provider "aws" {
  alias  = "master"
  region     = var.aws_region
}

#EXECUTION ROLE
data "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole"
}

### ECS

resource "aws_ecs_cluster" "main" {
  name = "ba-ecs-cluster"
}

data "aws_caller_identity" "current" {

}

resource "aws_ecs_task_definition" "app" {
  family                   = "stresstestapp"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = data.aws_iam_role.ecs_task_execution_role.arn

  container_definitions = <<DEFINITION
[
  {
    "cpu": ${var.fargate_cpu},
    "image": "${data.aws_caller_identity.current.account_id}.${var.app_image}",
    "memory": ${var.fargate_memory},
    "name": "stresstestapp",
    "networkMode": "awsvpc",
    "portMappings": [
      {
        "containerPort": ${var.app_port},
        "hostPort": ${var.app_port}
      },
      {
        "containerPort": 8186,
        "hostPort": 8186
      }
    ]
  },
  {
    "cpu": ${var.fargate_cpu},
    "image": "${data.aws_caller_identity.current.account_id}.${var.telegraf_image}",
    "memory": ${var.fargate_memory},
    "name": "telegraf",
    "networkMode": "awsvpc",
    "portMappings": [
      {
        "containerPort": 8086,
        "hostPort": 8086
      }
    ]
  }

]
DEFINITION
}

resource "aws_ecs_service" "main" {
  name            = "stresstestapp"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.app_count
  launch_type     = "FARGATE"

  network_configuration {
    security_groups = [
                  aws_security_group.ecs_tasks.id,
                  aws_security_group.ecs_public_sg.id
                      ]
    
    subnets         = flatten([aws_subnet.private.*.id])
  }

  load_balancer {
    target_group_arn = aws_alb_target_group.app.id
    container_name   = "stresstestapp"
    container_port   = var.app_port
  }

  depends_on = [
    aws_alb_listener.front_end,
    aws_subnet.private,
  ]
  health_check_grace_period_seconds = 600 # prevent task from being deregistered when we apply full stress on the task and health check fails  
}
