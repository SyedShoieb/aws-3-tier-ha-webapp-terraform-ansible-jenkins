# terraform/main.tf

provider "aws" {
  region = var.aws_region
}

# CloudFront WAF resources must be created in us-east-1.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }

  web_name = substr("${var.project_name}-web", 0, 32)
  app_name = substr("${var.project_name}-app", 0, 32)
}

# ---------------------------------------------------------
# IAM: allow EC2 instances to register with AWS Systems Manager
# ---------------------------------------------------------

resource "aws_iam_role" "web_instance" {
  name = "${var.project_name}-web-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role" "app_instance" {
  name = "${var.project_name}-app-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "web_ssm" {
  role       = aws_iam_role.web_instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "app_ssm" {
  role       = aws_iam_role.app_instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "web" {
  name = "${var.project_name}-web-instance-profile"
  role = aws_iam_role.web_instance.name

  tags = local.common_tags
}

resource "aws_iam_instance_profile" "app" {
  name = "${var.project_name}-app-instance-profile"
  role = aws_iam_role.app_instance.name

  tags = local.common_tags
}

# ---------------------------------------------------------
# Public Web Application Load Balancer
# ---------------------------------------------------------

resource "aws_lb" "web" {
  name               = local.web_name
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_alb.id]
  subnets            = values(aws_subnet.public)[*].id

  drop_invalid_header_fields = true
  idle_timeout               = 60

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-web-alb"
    Tier = "web"
  })
}

resource "aws_lb_target_group" "web" {
  name        = substr("${var.project_name}-web-tg", 0, 32)
  port        = 80
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = aws_vpc.main.id

  health_check {
    enabled             = true
    path                = "/nginx-health"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = merge(local.common_tags, {
    Tier = "web"
  })
}

resource "aws_lb_listener" "web_http" {
  load_balancer_arn = aws_lb.web.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }

  tags = local.common_tags
}

# ---------------------------------------------------------
# Private Application Load Balancer
# ---------------------------------------------------------

resource "aws_lb" "app" {
  name               = local.app_name
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.app_alb.id]
  subnets            = values(aws_subnet.app)[*].id

  drop_invalid_header_fields = true
  idle_timeout               = 60

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-app-alb"
    Tier = "application"
  })
}

resource "aws_lb_target_group" "app" {
  name        = substr("${var.project_name}-app-tg", 0, 32)
  port        = var.app_port
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = aws_vpc.main.id

  health_check {
    enabled             = true
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = merge(local.common_tags, {
    Tier = "application"
  })
}

resource "aws_lb_listener" "app_http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }

  tags = local.common_tags
}

# ---------------------------------------------------------
# EC2 launch templates
# ---------------------------------------------------------

resource "aws_launch_template" "web" {
  name_prefix   = "${var.project_name}-web-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.web_instance_type

  vpc_security_group_ids = [aws_security_group.web.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.web.name
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    set -e
    systemctl enable amazon-ssm-agent
    systemctl start amazon-ssm-agent
  EOF
  )

  tag_specifications {
    resource_type = "instance"

    tags = merge(local.common_tags, {
      Name = "${var.project_name}-web-instance"
      Tier = "web"
    })
  }

  tag_specifications {
    resource_type = "volume"

    tags = local.common_tags
  }

  depends_on = [
    aws_iam_role_policy_attachment.web_ssm
  ]

  tags = local.common_tags
}

resource "aws_launch_template" "app" {
  name_prefix   = "${var.project_name}-app-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.app_instance_type

  vpc_security_group_ids = [aws_security_group.app.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.app.name
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    set -e
    systemctl enable amazon-ssm-agent
    systemctl start amazon-ssm-agent
  EOF
  )

  tag_specifications {
    resource_type = "instance"

    tags = merge(local.common_tags, {
      Name = "${var.project_name}-app-instance"
      Tier = "application"
    })
  }

  tag_specifications {
    resource_type = "volume"

    tags = local.common_tags
  }

  depends_on = [
    aws_iam_role_policy_attachment.app_ssm
  ]

  tags = local.common_tags
}

# ---------------------------------------------------------
# Web Auto Scaling Group
# ---------------------------------------------------------

resource "aws_autoscaling_group" "web" {
  name                = "${var.project_name}-web-asg"
  min_size            = var.web_min_size
  desired_capacity    = var.web_desired_capacity
  max_size            = var.web_max_size
  vpc_zone_identifier = values(aws_subnet.web)[*].id

  target_group_arns = [
    aws_lb_target_group.web.arn
  ]

  health_check_type         = "ELB"
  health_check_grace_period = 600
  wait_for_capacity_timeout = "0"

  launch_template {
    id      = aws_launch_template.web.id
    version = "$Latest"
  }

  dynamic "tag" {
    for_each = merge(local.common_tags, {
      Name = "${var.project_name}-web-instance"
      Tier = "web"
    })

    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  depends_on = [
    aws_lb_listener.web_http
  ]
}

# ---------------------------------------------------------
# Application Auto Scaling Group
# ---------------------------------------------------------

resource "aws_autoscaling_group" "app" {
  name                = "${var.project_name}-app-asg"
  min_size            = var.app_min_size
  desired_capacity    = var.app_desired_capacity
  max_size            = var.app_max_size
  vpc_zone_identifier = values(aws_subnet.app)[*].id

  target_group_arns = [
    aws_lb_target_group.app.arn
  ]

  health_check_type         = "ELB"
  health_check_grace_period = 600
  wait_for_capacity_timeout = "0"

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  dynamic "tag" {
    for_each = merge(local.common_tags, {
      Name = "${var.project_name}-app-instance"
      Tier = "application"
    })

    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  depends_on = [
    aws_lb_listener.app_http
  ]
}

# ---------------------------------------------------------
# Private RDS MySQL database
# ---------------------------------------------------------

resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnets"
  subnet_ids = values(aws_subnet.db)[*].id

  description = "Private database subnets across the selected Availability Zones"

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-db-subnet-group"
  })
}

resource "aws_db_instance" "main" {
  identifier = "${var.project_name}-mysql"

  engine                = "mysql"
  instance_class        = var.db_instance_class
  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.db_name
  username = "appadmin"
  port     = var.db_port

  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false

  multi_az                   = var.db_multi_az
  backup_retention_period    = var.db_multi_az ? 7 : 1
  auto_minor_version_upgrade = true
  apply_immediately          = true

  deletion_protection = false
  skip_final_snapshot = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-mysql"
    Tier = "database"
  })
}

# Let only the application EC2 role retrieve the RDS-managed password.
resource "aws_iam_role_policy" "app_read_db_secret" {
  name = "${var.project_name}-read-db-secret"
  role = aws_iam_role.app_instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ]
      Resource = aws_db_instance.main.master_user_secret[0].secret_arn
    }]
  })
}

# ---------------------------------------------------------
# CloudWatch alarms for EC2 Auto Scaling Groups
# ---------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "web_high_cpu" {
  alarm_name          = "${var.project_name}-web-high-cpu"
  alarm_description   = "Average CPU usage in the web Auto Scaling Group is high"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.web.name
  }

  treat_missing_data = "notBreaching"
  tags               = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "app_high_cpu" {
  alarm_name          = "${var.project_name}-app-high-cpu"
  alarm_description   = "Average CPU usage in the application Auto Scaling Group is high"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.app.name
  }

  treat_missing_data = "notBreaching"
  tags               = local.common_tags
}

# ---------------------------------------------------------
# Optional CloudFront distribution and WAF
# ---------------------------------------------------------

resource "aws_wafv2_web_acl" "edge" {
  count    = var.enable_edge_services ? 1 : 0
  provider = aws.us_east_1

  name  = "${var.project_name}-cloudfront-waf"
  scope = "CLOUDFRONT"

  default_action {
    allow {}
  }

  rule {
    name     = "AWSManagedCommonRules"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "common-rules"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedKnownBadInputs"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "known-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-waf"
    sampled_requests_enabled   = true
  }

  tags = local.common_tags
}

resource "aws_cloudfront_distribution" "web" {
  count = var.enable_edge_services ? 1 : 0

  enabled         = true
  is_ipv6_enabled = true
  comment         = "CloudFront distribution for ${var.project_name}"
  price_class     = "PriceClass_100"
  web_acl_id      = aws_wafv2_web_acl.edge[0].arn

  origin {
    domain_name = aws_lb.web.dns_name
    origin_id   = "web-application-load-balancer"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "web-application-load-balancer"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = [
      "GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"
    ]

    cached_methods = ["GET", "HEAD"]

    # Static content can be cached at the edge.
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"

    compress = true
  }

  ordered_cache_behavior {
    path_pattern           = "/api*"
    target_origin_id       = "web-application-load-balancer"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = [
      "GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"
    ]

    cached_methods = ["GET", "HEAD"]

    # API responses should not be cached.
    cache_policy_id          = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    origin_request_policy_id = "216adef6-5c7f-47e4-b989-5492eafa07d3"

    compress = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = local.common_tags

  depends_on = [
    aws_lb_listener.web_http
  ]
}
