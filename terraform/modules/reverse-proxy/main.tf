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

# Elastic IP — static public IP for Route53 weighted record (avoids IP change on restart)
resource "aws_eip" "reverse_proxy" {
  domain = "vpc"
  tags   = { Name = "${var.app_name}-reverse-proxy-eip" }
}

resource "aws_eip_association" "reverse_proxy" {
  instance_id   = aws_instance.reverse_proxy.id
  allocation_id = aws_eip.reverse_proxy.id
}

# Reverse proxy EC2 instance running Nginx — sits in front of the ALB
resource "aws_instance" "reverse_proxy" {
  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = "t3.micro"
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [var.security_group_id]
  associate_public_ip_address = false # EIP handles public IP

  # Require IMDSv2 token — prevents SSRF attacks from leaking instance metadata
  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  # Encrypt root volume at rest
  root_block_device {
    encrypted = true
  }

  # Install and configure Nginx as reverse proxy
  # Uses AWS VPC DNS resolver (169.254.169.253) to resolve Cloud Map or ALB DNS dynamically
  user_data = <<-EOF
    #!/bin/bash
    dnf install -y nginx

    cat > /etc/nginx/conf.d/reverse-proxy.conf <<NGINX
    server {
      listen 80;
      server_name ${var.domain_name};

      # AWS VPC DNS resolver — required for dynamic DNS resolution (Cloud Map, ALB)
      resolver 169.254.169.253 valid=10s;
      set \$upstream ${var.upstream_url};

      location / {
        proxy_pass http://\$upstream;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
      }
    }
    NGINX

    systemctl enable nginx
    systemctl start nginx
  EOF

  tags = { Name = "${var.app_name}-reverse-proxy" }
}
