resource "aws_security_group" "web_alb" {
  name        = "${var.project_name}-web-alb-sg"
  description = "Allow public HTTP and HTTPS traffic to the web load balancer"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Public HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Public HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress = []

  tags = {
    Name = "${var.project_name}-web-alb-sg"
  }
}

resource "aws_security_group" "web" {
  name        = "${var.project_name}-web-sg"
  description = "Allow web traffic only from the public web load balancer"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Traffic from web ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.web_alb.id]
  }

  egress = []

  tags = {
    Name = "${var.project_name}-web-sg"
  }
}

resource "aws_security_group" "app_alb" {
  name        = "${var.project_name}-app-alb-sg"
  description = "Allow application traffic only from the web tier"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTP from web tier"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id]
  }

  egress = []

  tags = {
    Name = "${var.project_name}-app-alb-sg"
  }
}

resource "aws_security_group" "app" {
  name        = "${var.project_name}-app-sg"
  description = "Allow application traffic only from the internal application load balancer"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Node.js application traffic"
    from_port       = var.app_port
    to_port         = var.app_port
    protocol        = "tcp"
    security_groups = [aws_security_group.app_alb.id]
  }

  egress = []

  tags = {
    Name = "${var.project_name}-app-sg"
  }
}

resource "aws_security_group" "db" {
  name        = "${var.project_name}-db-sg"
  description = "Allow MySQL traffic only from the application tier"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "MySQL from application tier"
    from_port       = var.db_port
    to_port         = var.db_port
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  egress = []

  tags = {
    Name = "${var.project_name}-db-sg"
  }
}

resource "aws_vpc_security_group_egress_rule" "web_alb_to_web" {
  security_group_id            = aws_security_group.web_alb.id
  referenced_security_group_id = aws_security_group.web.id
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
  description                  = "Forward traffic to web instances"
}

resource "aws_vpc_security_group_egress_rule" "web_to_app_alb" {
  security_group_id            = aws_security_group.web.id
  referenced_security_group_id = aws_security_group.app_alb.id
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
  description                  = "Allow web tier to reach internal application ALB"
}

resource "aws_vpc_security_group_egress_rule" "app_alb_to_app" {
  security_group_id            = aws_security_group.app_alb.id
  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
  description                  = "Forward traffic to application instances"
}

resource "aws_vpc_security_group_egress_rule" "app_to_db" {
  security_group_id            = aws_security_group.app.id
  referenced_security_group_id = aws_security_group.db.id
  ip_protocol                  = "tcp"
  from_port                    = var.db_port
  to_port                      = var.db_port
  description                  = "Allow application tier to reach MySQL"
}

resource "aws_vpc_security_group_egress_rule" "web_https_outbound" {
  security_group_id = aws_security_group.web.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "Allow HTTPS outbound for required downloads and APIs"
}

resource "aws_vpc_security_group_egress_rule" "app_https_outbound" {
  security_group_id = aws_security_group.app.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "Allow HTTPS outbound for required downloads and APIs"
}
