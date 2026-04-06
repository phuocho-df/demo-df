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

# IAM role for EC2 — grants certbot permission to create Route53 TXT records (DNS-01 challenge)
resource "aws_iam_role" "reverse_proxy" {
  name = "${var.app_name}-reverse-proxy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

# tfsec:ignore:aws-iam-no-policy-wildcards — Route53 GetChange/ListHostedZones require wildcard resource
resource "aws_iam_role_policy" "certbot_route53" {
  name = "${var.app_name}-certbot-route53"
  role = aws_iam_role.reverse_proxy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "route53:GetChange",
          "route53:ChangeResourceRecordSets",
          "route53:ListHostedZones",
          "route53:ListResourceRecordSets",
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "reverse_proxy" {
  name = "${var.app_name}-reverse-proxy-profile"
  role = aws_iam_role.reverse_proxy.name
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

# Reverse proxy EC2 instance running Nginx with Let's Encrypt SSL
resource "aws_instance" "reverse_proxy" {
  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = "t3.micro"
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [var.security_group_id]
  associate_public_ip_address = false # EIP handles public IP
  iam_instance_profile        = aws_iam_instance_profile.reverse_proxy.name

  # Require IMDSv2 token — prevents SSRF attacks from leaking instance metadata
  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  # Encrypt root volume at rest
  root_block_device {
    encrypted = true
  }

  # Install Nginx + certbot, obtain Let's Encrypt cert via Route53 DNS-01 challenge,
  # then configure Nginx to terminate SSL and proxy to upstream (Cloud Map or ALB DNS).
  user_data = <<-EOF
    #!/bin/bash
    set -e

    # Install nginx and certbot with Route53 DNS plugin
    dnf install -y nginx python3-pip
    pip3 install certbot certbot-dns-route53

    # Obtain SSL certificate via DNS-01 challenge (no HTTP dependency — works with weighted DNS)
    certbot certonly \
      --dns-route53 \
      --non-interactive \
      --agree-tos \
      --email ${var.certbot_email} \
      -d ${var.domain_name} \
      --dns-route53-propagation-seconds 60

    # Configure Nginx: HTTP → HTTPS redirect + HTTPS reverse proxy to upstream
    cat > /etc/nginx/conf.d/reverse-proxy.conf <<NGINX
    # Redirect all HTTP to HTTPS
    server {
      listen 80;
      server_name ${var.domain_name};
      return 301 https://\$host\$request_uri;
    }

    # HTTPS reverse proxy — terminates SSL, forwards to upstream over HTTP
    server {
      listen 443 ssl;
      server_name ${var.domain_name};

      ssl_certificate     /etc/letsencrypt/live/${var.domain_name}/fullchain.pem;
      ssl_certificate_key /etc/letsencrypt/live/${var.domain_name}/privkey.pem;

      # AWS VPC DNS resolver — required for dynamic DNS resolution (Cloud Map, ALB)
      resolver 169.254.169.253 valid=10s;
      set \$upstream ${var.upstream_url};

      location / {
        proxy_pass http://\$upstream;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
      }
    }
    NGINX

    # Auto-renew cert twice daily
    echo "0 0,12 * * * root certbot renew --quiet --deploy-hook 'nginx -s reload'" >> /etc/crontab

    systemctl enable nginx
    systemctl start nginx
  EOF

  tags = { Name = "${var.app_name}-reverse-proxy" }
}
