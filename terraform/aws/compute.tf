# ECR Repositories
resource "aws_ecr_repository" "backend" {
  name                 = "${var.project_name}-${var.environment}-backend"
  image_tag_mutability = "MUTABLE"
}

resource "aws_ecr_repository" "cms" {
  name                 = "${var.project_name}-${var.environment}-cms"
  image_tag_mutability = "MUTABLE"
}

resource "aws_ecr_repository" "keycloak" {
  name                 = "${var.project_name}-${var.environment}-keycloak"
  image_tag_mutability = "MUTABLE"
}

resource "aws_ecr_repository" "analytics" {
  name                 = "${var.project_name}-${var.environment}-analytics"
  image_tag_mutability = "MUTABLE"
}

# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-${var.environment}-cluster"
}

# Application Load Balancer
resource "aws_lb" "main" {
  name               = "${var.project_name}-${var.environment}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.public_1.id, aws_subnet.public_2.id]
}

# Target Groups
resource "aws_lb_target_group" "backend" {
  name        = "${var.project_name}-${var.environment}-tg-backend"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    path    = "/actuator/health"
    port    = "8080"
    matcher = "200-499"
  }
}

resource "aws_lb_target_group" "cms" {
  name        = "${var.project_name}-${var.environment}-tg-cms"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    path = "/"
    port = "3000"
    matcher = "200-399"
  }
}

resource "aws_lb_target_group" "keycloak" {
  name        = "${var.project_name}-${var.environment}-tg-keycloak"
  port        = 8180
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    path                = "/health/ready"
    port                = "9000"
    matcher             = "200-499"
    interval            = 15
    healthy_threshold   = 2
  }
}

resource "aws_lb_target_group" "analytics" {
  name        = "${var.project_name}-${var.environment}-tg-analytics"
  port        = 8001
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    path    = "/v1/health"
    port    = "8001"
    matcher = "200-299"
  }
}

# Listeners
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  # Default action goes to CMS
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.cms.arn
  }
}

# Listener Rules

# NextAuth routes (/api/auth/*) must go to CMS, not backend
# This rule must have higher priority (lower number) than the backend /api/* rule
resource "aws_lb_listener_rule" "cms_auth_rule" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 50

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.cms.arn
  }

  condition {
    path_pattern {
      values = ["/api/auth/*"]
    }
  }
}

resource "aws_lb_listener_rule" "analytics_rule" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 75

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.analytics.arn
  }

  condition {
    path_pattern {
      values = ["/v1/analytics/*", "/v1/observations/*", "/v1/copilot/*", "/v1/health"]
    }
  }
}

resource "aws_lb_listener_rule" "backend_rule" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }

  condition {
    path_pattern {
      values = ["/api/*", "/ws/*"]
    }
  }
}

resource "aws_lb_listener_rule" "keycloak_rule" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 200

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.keycloak.arn
  }

  condition {
    path_pattern {
      values = ["/auth/*", "/realms/*", "/resources/*", "/admin/*", "/js/*"]
    }
  }
}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "backend" {
  name              = "/ecs/${var.project_name}-${var.environment}-backend"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "cms" {
  name              = "/ecs/${var.project_name}-${var.environment}-cms"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "keycloak" {
  name              = "/ecs/${var.project_name}-${var.environment}-keycloak"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "analytics" {
  name              = "/ecs/${var.project_name}-${var.environment}-analytics"
  retention_in_days = 7
}

# Task Definitions
resource "aws_ecs_task_definition" "backend" {
  family                   = "${var.project_name}-${var.environment}-backend"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "backend"
      image     = "${aws_ecr_repository.backend.repository_url}:latest"
      essential = true
      portMappings = [
        {
          containerPort = 8080
          protocol      = "tcp"
        }
      ]
      environment = [
        { name = "SPRING_DATASOURCE_URL", value = "jdbc:postgresql://${aws_db_instance.postgres.endpoint}/${aws_db_instance.postgres.db_name}" },
        { name = "SPRING_DATASOURCE_USERNAME", value = aws_db_instance.postgres.username },
        { name = "SPRING_DATASOURCE_PASSWORD", value = var.db_password },
        { name = "SPRING_DATA_REDIS_HOST", value = aws_elasticache_cluster.redis.cache_nodes[0].address },
        { name = "REDIS_HOST", value = aws_elasticache_cluster.redis.cache_nodes[0].address },
        { name = "REDIS_PASSWORD", value = "auren_redis_dev" },
        { name = "KEYCLOAK_AUTH_SERVER_URL", value = "http://${aws_lb.main.dns_name}" },
        { name = "KEYCLOAK_ISSUER_URI", value = "http://${aws_lb.main.dns_name}/realms/auren" },
        { name = "KEYCLOAK_JWK_URI", value = "http://${aws_lb.main.dns_name}/realms/auren/protocol/openid-connect/certs" },
        { name = "KEYCLOAK_SERVER_URL", value = "http://${aws_lb.main.dns_name}" },
        { name = "KEYCLOAK_ADMIN_PASSWORD", value = var.keycloak_admin_password },
        { name = "CORS_ORIGINS", value = "http://${aws_lb.main.dns_name},http://localhost:3000" }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.backend.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

resource "aws_ecs_task_definition" "cms" {
  family                   = "${var.project_name}-${var.environment}-cms"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "cms"
      image     = "${aws_ecr_repository.cms.repository_url}:latest"
      essential = true
      portMappings = [
        {
          containerPort = 3000
          protocol      = "tcp"
        }
      ]
      environment = [
        { name = "NEXT_PUBLIC_API_URL", value = "http://${aws_lb.main.dns_name}/api" },
        { name = "KEYCLOAK_URL", value = "http://${aws_lb.main.dns_name}" },
        { name = "KEYCLOAK_ISSUER", value = "http://${aws_lb.main.dns_name}/realms/auren" },
        { name = "KEYCLOAK_ID", value = "auren-cms" },
        { name = "KEYCLOAK_SECRET", value = "dummy" },
        { name = "NEXTAUTH_URL", value = "http://${aws_lb.main.dns_name}" },
        { name = "NEXTAUTH_SECRET", value = "auren-preprod-nextauth-secret-change-in-prod" },
        { name = "NEXT_PUBLIC_ANALYTICS_URL", value = "http://${aws_lb.main.dns_name}" }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.cms.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

resource "aws_ecs_task_definition" "keycloak" {
  family                   = "${var.project_name}-${var.environment}-keycloak"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "keycloak"
      image     = "${aws_ecr_repository.keycloak.repository_url}:latest"
      essential = true
      portMappings = [
        {
          containerPort = 8180
          protocol      = "tcp"
        },
        {
          containerPort = 9000
          protocol      = "tcp"
        }
      ]
      environment = [
        { name = "KC_DB", value = "postgres" },
        { name = "KC_DB_URL", value = "jdbc:postgresql://${aws_db_instance.postgres.endpoint}/${aws_db_instance.postgres.db_name}" },
        { name = "KC_DB_USERNAME", value = aws_db_instance.postgres.username },
        { name = "KC_DB_PASSWORD", value = var.db_password },
        { name = "KC_PROXY_HEADERS", value = "xforwarded" },
        { name = "KC_HTTP_ENABLED", value = "true" },
        { name = "KC_HOSTNAME_STRICT", value = "false" },
        { name = "KC_HTTP_PORT", value = "8180" },
        { name = "KC_HEALTH_ENABLED", value = "true" },
        { name = "KC_METRICS_ENABLED", value = "true" },
        { name = "KEYCLOAK_ADMIN", value = "superadmin" },
        { name = "KEYCLOAK_ADMIN_PASSWORD", value = var.keycloak_admin_password }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.keycloak.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

# ECS Services
resource "aws_ecs_service" "backend" {
  name            = "${var.project_name}-${var.environment}-backend-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.backend.arn
  desired_count   = 1
  launch_type     = "FARGATE"
  health_check_grace_period_seconds = 300

  network_configuration {
    subnets         = [aws_subnet.private_1.id, aws_subnet.private_2.id]
    security_groups = [aws_security_group.ecs_sg.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.backend.arn
    container_name   = "backend"
    container_port   = 8080
  }
}

resource "aws_ecs_service" "cms" {
  name            = "${var.project_name}-${var.environment}-cms-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.cms.arn
  desired_count   = 1
  launch_type     = "FARGATE"
  health_check_grace_period_seconds = 120

  network_configuration {
    subnets         = [aws_subnet.private_1.id, aws_subnet.private_2.id]
    security_groups = [aws_security_group.ecs_sg.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.cms.arn
    container_name   = "cms"
    container_port   = 3000
  }
}

resource "aws_ecs_service" "keycloak" {
  name            = "${var.project_name}-${var.environment}-keycloak-service"
  cluster                 = aws_ecs_cluster.main.id
  task_definition         = aws_ecs_task_definition.keycloak.arn
  desired_count           = 1
  launch_type             = "FARGATE"
  enable_execute_command  = true
  health_check_grace_period_seconds = 300

  network_configuration {
    subnets         = [aws_subnet.private_1.id, aws_subnet.private_2.id]
    security_groups = [aws_security_group.ecs_sg.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.keycloak.arn
    container_name   = "keycloak"
    container_port   = 8180
  }
}

resource "aws_ecs_task_definition" "analytics" {
  family                   = "${var.project_name}-${var.environment}-analytics"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "analytics"
      image     = "${aws_ecr_repository.analytics.repository_url}:latest"
      essential = true
      portMappings = [
        {
          containerPort = 8001
          protocol      = "tcp"
        }
      ]
      environment = [
        { name = "DEFAULT_DATABASE_URL", value = "postgresql://${aws_db_instance.postgres.username}:${var.db_password}@${aws_db_instance.postgres.endpoint}/${aws_db_instance.postgres.db_name}" },
        { name = "KEYCLOAK_ISSUER", value = "http://${aws_lb.main.dns_name}/realms/auren" },
        { name = "KEYCLOAK_CERTS_URL", value = "http://${aws_lb.main.dns_name}/realms/auren/protocol/openid-connect/certs" },
        { name = "KEYCLOAK_AUDIENCE", value = "account" },
        { name = "CORS_ORIGINS", value = "http://${aws_lb.main.dns_name},http://localhost:3000" }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.analytics.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "analytics" {
  name            = "${var.project_name}-${var.environment}-analytics-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.analytics.arn
  desired_count   = 1
  launch_type     = "FARGATE"
  health_check_grace_period_seconds = 120

  network_configuration {
    subnets         = [aws_subnet.private_1.id, aws_subnet.private_2.id]
    security_groups = [aws_security_group.ecs_sg.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.analytics.arn
    container_name   = "analytics"
    container_port   = 8001
  }
}
