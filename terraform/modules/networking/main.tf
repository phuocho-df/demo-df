data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.app_name}-vpc" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "${var.app_name}-igw" }
}

# Public subnets — ALB and NAT Gateway run here
resource "aws_subnet" "public" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = { Name = "${var.app_name}-public-${count.index + 1}" }
}

# Private subnets — ECS tasks and RDS (no direct internet, routed via NAT Gateway)
resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = { Name = "${var.app_name}-private-${count.index + 1}" }
}

# Single NAT Gateway in first public subnet (one AZ to minimize cost ~$32/mo)
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = { Name = "${var.app_name}-nat-eip" }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = { Name = "${var.app_name}-nat" }

  depends_on = [aws_internet_gateway.main]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${var.app_name}-rt-public" }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private route table — routes outbound traffic through NAT Gateway
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = { Name = "${var.app_name}-rt-private" }
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# Security group: ALB — accepts HTTP/HTTPS from internet
resource "aws_security_group" "alb" {
  name        = "${var.app_name}-sg-alb"
  description = "Allow HTTP and HTTPS inbound to ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP" #tfsec:ignore:aws-ec2-no-public-ingress-sgr — public ALB requires internet ingress
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS" #tfsec:ignore:aws-ec2-no-public-ingress-sgr — public ALB requires internet ingress
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound to reach ECS targets" #tfsec:ignore:aws-ec2-no-public-egress-sgr — ALB must reach ECS tasks
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.app_name}-sg-alb" }
}

# Security group: ECS tasks — accepts port 80 from ALB only
resource "aws_security_group" "ecs" {
  name        = "${var.app_name}-sg-ecs"
  description = "Allow port 80 inbound from ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTP from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "All outbound for ECR/SSM/internet access" #tfsec:ignore:aws-ec2-no-public-egress-sgr — ECS tasks need internet for ECR pulls and SSM
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.app_name}-sg-ecs" }
}

# Security group: RDS — accepts port 5432 from ECS tasks and bastion host
resource "aws_security_group" "rds" {
  name        = "${var.app_name}-sg-rds"
  description = "Allow PostgreSQL inbound from ECS tasks and bastion host"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL from ECS"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
  }

  ingress {
    description     = "PostgreSQL from bastion (DB migration)"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  egress {
    description = "All outbound" #tfsec:ignore:aws-ec2-no-public-egress-sgr — RDS egress low risk, simplifies rule management
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.app_name}-sg-rds" }
}

# Security group: bastion host — SSH from internet, full egress
resource "aws_security_group" "bastion" {
  name        = "${var.app_name}-sg-bastion"
  description = "Allow SSH inbound from internet for DB migration access"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH" #tfsec:ignore:aws-ec2-no-public-ingress-sgr — bastion is the intentional public SSH entry point
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound for package installs" #tfsec:ignore:aws-ec2-no-public-egress-sgr — bastion needs internet for dnf/psql
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.app_name}-sg-bastion" }
}
