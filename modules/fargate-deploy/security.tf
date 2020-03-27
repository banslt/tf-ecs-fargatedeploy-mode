data "aws_instance" "deploy" {
 filter {
    name   = "tag:Name"
    values = ["ba_ecsdeploy"]
  }
}
data "aws_instance" "trafficgen" {
 filter {
    name   = "tag:Name"
    values = ["ba_ecstrafficgen"]
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
  vpc_id      = aws_vpc.main.id

  ingress {
    protocol    = "TCP"
    from_port   = var.app_port
    to_port     = var.app_port
    cidr_blocks = ["${data.aws_instance.deploy.public_ip}/32",
                   "${data.aws_instance.trafficgen.public_ip}/32"
                  ] # Allow communication with traffic gen on main instance
  }

  ingress {
    protocol    = "TCP"
    from_port   = 8086
    to_port     = 8086

    cidr_blocks = ["${data.aws_instance.monitoring.public_ip}/32"] # Allow influxDB queries on monitoring instance
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  depends_on = [ aws_vpc_peering_connection_accepter.master ]
}

#Allow inbound access from the ALB only for telegraf
resource "aws_security_group" "ecs_public_sg" {
  name        = "ecs_telegraf"
  description = "Allow telegraf ecs inbound traffic"
  vpc_id      = aws_vpc.main.id

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
    security_groups = [aws_security_group.lb.id]  
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
  vpc_id      = aws_vpc.main.id

  ingress {
    protocol        = "TCP"
    from_port       = var.app_port
    to_port         = var.app_port
    security_groups = [aws_security_group.lb.id]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Allow monitoring instance inbound access for influxdb queries and telegraf
resource "aws_security_group_rule" "monitoring_a" {
  security_group_id = "sg-0e6590742913d2fca"
  type            = "ingress"
  from_port       = 8086
  to_port         = 8086
  protocol        = "tcp"
  source_security_group_id = aws_security_group.lb.id
}
resource "aws_security_group_rule" "monitoring_b" {
  security_group_id = "sg-0e6590742913d2fca"
  type            = "ingress"
  from_port       = 8186
  to_port         = 8186
  protocol        = "tcp"
  source_security_group_id = aws_security_group.lb.id
}
resource "aws_security_group_rule" "monitoring_c" {
  security_group_id = "sg-0e6590742913d2fca"
  type            = "ingress"
  from_port       = 8086
  to_port         = 8086
  protocol        = "tcp"
  source_security_group_id = aws_security_group.ecs_tasks.id
}
resource "aws_security_group_rule" "monitoring_d" {
  security_group_id = "sg-0e6590742913d2fca"
  type            = "ingress"
  from_port       = 8186
  to_port         = 8186
  protocol        = "tcp"
  source_security_group_id = aws_security_group.ecs_tasks.id
}
