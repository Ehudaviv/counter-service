# ECR Repositories with Image Scanning enabled
resource "aws_ecr_repository" "backend" {
  name                 = "ehud-counter-backend"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_repository" "frontend" {
  name                 = "ehud-counter-frontend"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
}

# Generate a secure random password
resource "random_password" "db_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
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
  instance_class         = "db.t4g.micro" # ARM64
  allocated_storage      = 20
  storage_type           = "gp3"
  storage_encrypted      = true           
  username               = "postgres"
  password               = random_password.db_password.result
  db_subnet_group_name   = aws_db_subnet_group.rds.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  skip_final_snapshot    = true           
}

# Create the Secret in AWS Secrets Manager
resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "${var.cluster_name}-rds-credentials"
  recovery_window_in_days = 0 
}

# Store the generated password and connection details
resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id     = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = aws_db_instance.postgres.username
    password = random_password.db_password.result
    host     = aws_db_instance.postgres.address
    port     = aws_db_instance.postgres.port
  })
}