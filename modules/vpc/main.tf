data "aws_availability_zones" "available" {
  state = "available"
}

# ─── VPC ──────────────────────────────────────────────────────────────────────
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "${var.project}-${var.environment}-vpc"
    Project     = var.project
    Environment = var.environment
  }
}

# ─── SUBNETS ──────────────────────────────────────────────────────────────────
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.project}-${var.environment}-public-${count.index + 1}"
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name        = "${var.project}-${var.environment}-private-${count.index + 1}"
    Project     = var.project
    Environment = var.environment
  }
}

# ─── INTERNET GATEWAY ─────────────────────────────────────────────────────────
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "${var.project}-${var.environment}-igw"
    Project     = var.project
    Environment = var.environment
  }
}

# ─── NAT GATEWAY ──────────────────────────────────────────────────────────────
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name        = "${var.project}-${var.environment}-eip-nat"
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  depends_on    = [aws_internet_gateway.main]

  tags = {
    Name        = "${var.project}-${var.environment}-nat"
    Project     = var.project
    Environment = var.environment
  }
}

# ─── ROUTE TABLES ─────────────────────────────────────────────────────────────
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name        = "${var.project}-${var.environment}-rt-public"
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name        = "${var.project}-${var.environment}-rt-private"
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# ─── VPC ENDPOINT GATEWAY PARA S3 ────────────────────────────────────────────
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = {
    Name        = "${var.project}-${var.environment}-vpce-s3"
    Project     = var.project
    Environment = var.environment
  }
}

# ─── SECURITY GROUPS ──────────────────────────────────────────────────────────
resource "aws_security_group" "lambda" {
  name        = "${var.project}-${var.environment}-sg-lambda"
  description = "Trafico saliente de Lambda: HTTPS hacia AWS APIs y Redis hacia ElastiCache"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "HTTPS hacia AWS APIs (SDK, S3 via endpoint)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project}-${var.environment}-sg-lambda"
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_security_group" "redis" {
  name        = "${var.project}-${var.environment}-sg-redis"
  description = "Acceso a Redis unicamente desde el Security Group de Lambda"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Redis desde Lambda"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda.id]
  }

  tags = {
    Name        = "${var.project}-${var.environment}-sg-redis"
    Project     = var.project
    Environment = var.environment
  }
}

# Regla separada para evitar dependencia circular entre SGs
resource "aws_security_group_rule" "lambda_to_redis" {
  type                     = "egress"
  description              = "Lambda hacia Redis"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  security_group_id        = aws_security_group.lambda.id
  source_security_group_id = aws_security_group.redis.id
}
