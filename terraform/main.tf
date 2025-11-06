terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-west-2"
}

####################
# VPC & Subnets
####################
resource "aws_vpc" "dilivio-project" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"

  tags = {
    Name = "multistack-project-ds"
  }
}

# Public subnet (frontend)
resource "aws_subnet" "public-sub-d" {
  vpc_id                  = aws_vpc.dilivio-project.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet-ds"
  }
}

# Private subnet (backend + database)
resource "aws_subnet" "private-subnet-d" {
  vpc_id                  = aws_vpc.dilivio-project.id
  cidr_block              = "10.0.5.0/24"
  map_public_ip_on_launch = false

  tags = {
    Name = "private-subnet-ds"
  }
}

####################
# Internet & NAT
####################
resource "aws_internet_gateway" "gw-dilivio" {
  vpc_id = aws_vpc.dilivio-project.id

  tags = {
    Name = "igw-ds"
  }
}

resource "aws_eip" "nat-ds" {
  domain = "vpc"
}

resource "aws_nat_gateway" "nat-dilivio" {
  allocation_id = aws_eip.nat-ds.id
  subnet_id     = aws_subnet.public-sub-d.id

  tags = {
    Name = "gw-NAT-ds"
  }

  depends_on = [aws_internet_gateway.gw-dilivio]
}

####################
# Route tables
####################
# Public route table
resource "aws_route_table" "public-ds" {
  vpc_id = aws_vpc.dilivio-project.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw-dilivio.id
  }

  tags = {
    Name = "public-route-ds"
  }
}

resource "aws_route_table_association" "pub-dilivio" {
  subnet_id      = aws_subnet.public-sub-d.id
  route_table_id = aws_route_table.public-ds.id
}

# Private route table
resource "aws_route_table" "private-ds" {
  vpc_id = aws_vpc.dilivio-project.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat-dilivio.id
  }

  tags = {
    Name = "private-route-ds"
  }
}

resource "aws_route_table_association" "prive-dilivio" {
  subnet_id      = aws_subnet.private-subnet-d.id
  route_table_id = aws_route_table.private-ds.id
}

####################
# Security Groups
####################
# Public security group (frontend)
resource "aws_security_group" "public-security-ds" {
  name        = "public-security-rules"
  description = "Allow inbound traffic and outbound traffic"
  vpc_id      = aws_vpc.dilivio-project.id

  tags = {
    Name = "public-security-ds"
  }
}

# Public inbound rules
resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.public-security-ds.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  security_group_id = aws_security_group.public-security-ds.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.public-security-ds.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "allow_all_outbound" {
  security_group_id = aws_security_group.public-security-ds.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# Private security group (backend + database)
resource "aws_security_group" "private-security-ds" {
  name        = "private-security-rules"
  description = "Allow SSH, Redis, Postgres from VPC"
  vpc_id      = aws_vpc.dilivio-project.id

  tags = {
    Name = "private-security-ds"
  }
}

# SSH within VPC
resource "aws_vpc_security_group_ingress_rule" "ssh-intern" {
  security_group_id = aws_security_group.private-security-ds.id
  cidr_ipv4         = aws_vpc.dilivio-project.cidr_block
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}

# Redis (6379) accessible from frontend subnet
resource "aws_vpc_security_group_ingress_rule" "redis-from-frontend" {
  security_group_id = aws_security_group.private-security-ds.id
  cidr_ipv4         = aws_subnet.public-sub-d.cidr_block
  from_port         = 6379
  to_port           = 6379
  ip_protocol       = "tcp"
}

# Postgres (5432) accessible from backend subnet (Worker)
resource "aws_vpc_security_group_ingress_rule" "postgres-from-backend" {
  security_group_id = aws_security_group.private-security-ds.id
  cidr_ipv4         = aws_subnet.private-subnet-d.cidr_block
  from_port         = 5432
  to_port           = 5432
  ip_protocol       = "tcp"
}

# Outbound all allowed for private
resource "aws_vpc_security_group_egress_rule" "private-allow-outbound" {
  security_group_id = aws_security_group.private-security-ds.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

####################
# EC2 Instances
####################
# Frontend (Vote + Result)
resource "aws_instance" "ec2-pub" {
  ami                    = "ami-00f46ccd1cbfb363e"
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public-sub-d.id
  vpc_security_group_ids = [aws_security_group.public-security-ds.id]
  key_name               = "public-dds"

  tags = {
    Name = "pub-instance-ds"
  }
}

# Backend (Worker + Redis)
resource "aws_instance" "ec2-private" {
  ami                    = "ami-00f46ccd1cbfb363e"
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.private-subnet-d.id
  vpc_security_group_ids = [aws_security_group.private-security-ds.id]
  key_name               = "private-dds"

  tags = {
    Name = "pri-instanceB-ds"
  }
}

# Database (Postgres)
resource "aws_instance" "ec2-private-C" {
  ami                    = "ami-00f46ccd1cbfb363e"
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.private-subnet-d.id
  vpc_security_group_ids = [aws_security_group.private-security-ds.id]
  key_name               = "private-dds"

  tags = {
    Name = "pri-instanceC-ds"
  }
}

####################
# DynamoDB for Terraform State Locking
####################
resource "aws_dynamodb_table" "terraform_state_lock" {
  name         = "terraform-state-lock-ds"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name = "Terraform State Locking"
  }
}
