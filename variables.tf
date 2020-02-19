variable "aws_region" {
  default     = "us-east-2"
}

variable "az_count" {
  description = "Number of AZs to cover in a given AWS region"
  default     = "2"
}

variable "app_image" {
  description = "Docker image to run in the ECS cluster"
  default     = "189141687483.dkr.ecr.us-east-2.amazonaws.com/stresstestapp:latest"
}

variable "telegraf_image" {
  description = "telegraf docker image to run in the ECS cluster"
  default     = "189141687483.dkr.ecr.us-east-2.amazonaws.com/ba/telegraf-ecs:latest"
}

variable "app_port" {
  description = "Port exposed by the docker image to redirect traffic to"
  default     = 3100
}

variable "app_count" {
  description = "Number of docker containers to run"
  default     = 2
}

variable "fargate_cpu" {
  description = "Fargate instance CPU units to provision (1 vCPU = 1024 CPU units)"
  default     = "256"
}

variable "fargate_memory" {
  description = "Fargate instance memory to provision (in MiB)"
  default     = "512"
}
