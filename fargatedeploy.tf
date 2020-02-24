provider "aws" {
  region     = "${var.aws_region}"
}

### Network

# Fetch AZs in the current region
data "aws_availability_zones" "available" {}

data "aws_vpc" "main" {
  cidr_block = "172.22.0.0/16"
}

# Create var.az_count private subnets, each in a different AZ
resource "aws_subnet" "private" {
  count             = "${var.az_count}"
  cidr_block        = "${cidrsubnet(data.aws_vpc.main.cidr_block, 8, count.index+1)}"
  availability_zone = "${data.aws_availability_zones.available.names[count.index]}"
  vpc_id            = "${data.aws_vpc.main.id}"
}

# Create var.az_count public subnets, each in a different AZ
resource "aws_subnet" "public" {
  count                   = "${var.az_count}"
  cidr_block              = "${cidrsubnet(data.aws_vpc.main.cidr_block, 8, var.az_count + count.index+1)}"
  availability_zone       = "${data.aws_availability_zones.available.names[count.index]}"
  vpc_id                  = "${data.aws_vpc.main.id}"
  map_public_ip_on_launch = true
}


# IGW for the public subnet
data "aws_internet_gateway" "gw" {
  filter {
    name   = "attachment.vpc-id"
    values = ["${data.aws_vpc.main.id}"]
  }
}

# Route the public subnet traffic through the IGW
resource "aws_route" "internet_access" {
  route_table_id         = "${data.aws_vpc.main.main_route_table_id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = "${data.aws_internet_gateway.gw.id}"
}

# Create a NAT gateway with an EIP for each private subnet to get internet connectivity
resource "aws_eip" "gw" {
  count      = "${var.az_count}"
  vpc        = true
  depends_on = [data.aws_internet_gateway.gw]
}

resource "aws_nat_gateway" "gw" {
  count         = "${var.az_count}"
  subnet_id     = "${element(aws_subnet.public.*.id, count.index)}"
  allocation_id = "${element(aws_eip.gw.*.id, count.index)}"
}

# Create a new route table for the private subnets
# And make it route non-local traffic through the NAT gateway to the internet
resource "aws_route_table" "private" {
  count  = "${var.az_count}"
  vpc_id = "${data.aws_vpc.main.id}"

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = "${element(aws_nat_gateway.gw.*.id, count.index)}"
  }
}

# Explicitely associate the newly created route tables to the private subnets (so they don't default to the main route table)
resource "aws_route_table_association" "private" {
  count          = "${var.az_count}"
  subnet_id      = "${element(aws_subnet.private.*.id, count.index)}"
  route_table_id = "${element(aws_route_table.private.*.id, count.index)}"
}

### Security

data "aws_instance" "trafficgen" {
 filter {
    name   = "tag:Name"
    values = ["ba_ecsdeploy"]
  }
}
data "aws_instance" "monitoring" {
 filter {
    name   = "tag:Name"
    values = ["ba-ecsmonitoring"]
  }
}

# ALB Security group
# This is the group you need to edit if you want to restrict access to your application
resource "aws_security_group" "lb" {
  name        = "ba-ecs-alb"
  description = "controls access to the ALB"
  vpc_id      = "${data.aws_vpc.main.id}"

  ingress {
    protocol    = "TCP"
    from_port   = "${var.app_port}"
    to_port     = "${var.app_port}"
    cidr_blocks = ["${data.aws_instance.trafficgen.public_ip}/32"]
  }

  ingress {
    protocol    = "TCP"
    from_port   = 8086
    to_port     = 8086
    cidr_blocks = ["${data.aws_instance.monitoring.public_ip}/32"]
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#Allow inbound access from the ALB only for telegraf
resource "aws_security_group" "ecs_public_sg" {
  name        = "ecs_telegraf"
  description = "Allow telegraf ecs inbound traffic"
  vpc_id      = "${data.aws_vpc.main.id}"

  ingress {
    from_port       = 8086
    to_port         = 8086
    protocol        = "TCP"
    cidr_blocks = ["${data.aws_instance.monitoring.public_ip}/32"]  
  }
  
  ingress {
    from_port       = 8086
    to_port         = 8086
    protocol        = "TCP"
    security_groups = ["${aws_security_group.lb.id}"]  
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#Allow inbound access from the ALB only for the service
resource "aws_security_group" "ecs_tasks" {
  name        = "ba-ecs-tasks"
  description = "allow inbound access from the ALB only"
  vpc_id      = "${data.aws_vpc.main.id}"

  ingress {
    protocol        = "TCP"
    from_port       = "${var.app_port}"
    to_port         = "${var.app_port}"
    security_groups = ["${aws_security_group.lb.id}"]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

### ALB

resource "aws_alb" "main" {
  name            = "ba-ecs-alb"
  subnets         = flatten([aws_subnet.public.*.id])
  security_groups = ["${aws_security_group.lb.id}"]
  depends_on = [
    aws_subnet.public,
  ]

}

resource "aws_alb_target_group" "app" {
  name        = "ba-tg-stressapp"
  port        = 3100
  protocol    = "HTTP"
  vpc_id      = "${data.aws_vpc.main.id}"
  target_type = "ip"
}

resource "aws_alb_target_group" "telegraf" {
  name        = "ba-tg-telegraf"
  port        = 8086
  protocol    = "HTTP"
  vpc_id      = "${data.aws_vpc.main.id}"
  target_type = "ip"
}

# Redirect all traffic from the ALB to the target group
resource "aws_alb_listener" "front_end" {
  load_balancer_arn = "${aws_alb.main.id}"
  port              = "3100"
  protocol          = "HTTP"

  default_action {
    target_group_arn = "${aws_alb_target_group.app.id}"
    type             = "forward"
  }
}


#EXECUTION ROLE
data "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole"
}

### ECS

resource "aws_ecs_cluster" "main" {
  name = "ba-ecs-cluster"
}

resource "aws_ecs_task_definition" "app" {
  family                   = "stresstestapp"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = "${data.aws_iam_role.ecs_task_execution_role.arn}"

  container_definitions = <<DEFINITION
[
  {
    "cpu": ${var.fargate_cpu},
    "image": "${var.app_image}",
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
    "image": "${var.telegraf_image}",
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
  cluster         = "${aws_ecs_cluster.main.id}"
  task_definition = "${aws_ecs_task_definition.app.arn}"
  desired_count   = "${var.app_count}"
  launch_type     = "FARGATE"

  network_configuration {
    security_groups = [
                  "${aws_security_group.ecs_tasks.id}",
                  "${aws_security_group.ecs_public_sg.id}"
                      ]
    
    subnets         = concat(flatten([aws_subnet.private.*.id]),flatten([aws_subnet.public.*.id]))
  }

  load_balancer {
    target_group_arn = "${aws_alb_target_group.app.id}"
    container_name   = "stresstestapp"
    container_port   = "${var.app_port}"
  }

  depends_on = [
    aws_alb_listener.front_end,
    aws_subnet.private,
  ]
}

# ECS Svc AS

module "svc-scaling" {
  source          = "./modules/svc-scaling"
  cluster_name    = "${aws_ecs_cluster.main.name}"
  service_name    = "${aws_ecs_service.main.name}"
  alarm_name      = "ba_cpu_stressapp"
  scale_policy_name_prefix = "ba_stressapp"
}




