resource "aws_alb" "main" {
  name            = "ba-ecs-alb"
  subnets         = flatten([aws_subnet.public.*.id])
  security_groups = [aws_security_group.lb.id]
  depends_on = [
    aws_subnet.public,
  ]
  provisioner "local-exec" {
    command = "echo ${aws_alb.main.dns_name} > ../../lb_addr/loadbalancer_address"
  }
}

resource "aws_alb_target_group" "app" {
  name        = "ba-tg-stressapp"
  port        = 3100
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"
  deregistration_delay = 10
}

# Redirect all traffic from the ALB to the target group
resource "aws_alb_listener" "front_end" {
  load_balancer_arn = aws_alb.main.id
  port              = "3100"
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_alb_target_group.app.id
    type             = "forward"
  }
}
