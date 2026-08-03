output "alb_dns_name" {
  description = "The DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "rds_endpoint" {
  description = "The connection endpoint for the RDS PostgreSQL database"
  value       = aws_db_instance.postgres.endpoint
}

output "redis_endpoint" {
  description = "The connection endpoint for the ElastiCache Redis cluster"
  value       = aws_elasticache_cluster.redis.cache_nodes[0].address
}

output "ecr_repository_backend" {
  description = "The ECR repository URL for the backend"
  value       = aws_ecr_repository.backend.repository_url
}

output "ecr_repository_cms" {
  description = "The ECR repository URL for the CMS"
  value       = aws_ecr_repository.cms.repository_url
}

output "ecr_repository_keycloak" {
  description = "The ECR repository URL for Keycloak"
  value       = aws_ecr_repository.keycloak.repository_url
}

output "ecr_repository_analytics" {
  description = "The ECR repository URL for Analytics"
  value       = aws_ecr_repository.analytics.repository_url
}
