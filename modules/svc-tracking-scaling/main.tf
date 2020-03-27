resource "aws_appautoscaling_policy" "scale" {
  name               = "${var.scale_policy_name_prefix}-scale"
  policy_type        = "TargetTrackingScaling"
  resource_id        = "service/${var.cluster_name}/${var.service_name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"

  target_tracking_scaling_policy_configuration {
    target_value = 60
    scale_in_cooldown = 10
    scale_out_cooldown = 5

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}
