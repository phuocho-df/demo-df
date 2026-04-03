# Fetch latest Amazon Linux 2023 AMI (x86_64, HVM)
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# SSH key pair — public key content supplied via variable
resource "aws_key_pair" "bastion" {
  key_name   = "${var.app_name}-bastion-key"
  public_key = var.public_key

  tags = { Name = "${var.app_name}-bastion-key" }
}

resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [var.security_group_id]
  key_name                    = aws_key_pair.bastion.key_name
  associate_public_ip_address = true

  # Require IMDSv2 token — prevents SSRF attacks from leaking instance metadata
  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  # Encrypt root volume at rest
  root_block_device {
    encrypted = true
  }

  # Install PostgreSQL 15 client so pg_dump/psql can run directly on the bastion
  user_data = <<-EOF
    #!/bin/bash
    dnf install -y postgresql15
  EOF

  tags = { Name = "${var.app_name}-bastion" }
}
