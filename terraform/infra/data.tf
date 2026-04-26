# ECR Repositories with Image Scanning enabled
resource "aws_ecr_repository" "backend" {
  name                 = "counter-backend"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_repository" "frontend" {
  name                 = "counter-frontend"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
}

# RDS Subnet Group
resource "aws_db_subnet_group" "rds" {
  name       = "${var.cluster_name}-rds-subnet-group"
  subnet_ids = module.vpc.private_subnets
}

# RDS Security Group (Allow access from VPC)
resource "aws_security_group" "rds" {
  name   = "${var.cluster_name}-rds-sg"
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [module.vpc.vpc_cidr_block]
  }
}

# The PostgreSQL Database
resource "aws_db_instance" "postgres" {
  identifier             = "${var.cluster_name}-db"
  engine                 = "postgres"
  engine_version         = "16"
  instance_class         = "db.t4g.micro" # ARM64 for cost efficiency
  allocated_storage      = 20
  storage_type           = "gp3"
  storage_encrypted      = true           # Mandatory per requirements
  username               = "postgres"
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.rds.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  skip_final_snapshot    = true           # Useful for test assignments
}   