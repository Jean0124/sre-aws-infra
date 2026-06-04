# ─── SUBNET GROUP ────────────────────────────────────────────────────────────
resource "aws_elasticache_subnet_group" "redis" {
  name       = "${var.project}-${var.environment}-redis-subnet-group"
  subnet_ids = var.subnet_ids

  tags = {
    Name        = "${var.project}-${var.environment}-redis-subnet-group"
    Project     = var.project
    Environment = var.environment
  }
}

# ─── CLUSTER REDIS ───────────────────────────────────────────────────────────
resource "aws_elasticache_cluster" "redis" {
  cluster_id           = "${var.project}-${var.environment}-redis"
  engine               = "redis"
  node_type            = "cache.t3.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  engine_version       = "7.0"
  port                 = 6379

  subnet_group_name  = aws_elasticache_subnet_group.redis.name
  security_group_ids = [var.security_group_id]

  # Sin snapshots — caché efímera, no persistencia indefinida
  snapshot_retention_limit = 0

  tags = {
    Name        = "${var.project}-${var.environment}-redis"
    Project     = var.project
    Environment = var.environment
  }
}
