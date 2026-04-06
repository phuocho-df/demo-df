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

# IAM role for EC2 — grants certbot Route53 permission + S3 cert backup/restore
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

# SSM managed instance — enables Session Manager access without SSH key
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.reverse_proxy.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# tfsec:ignore:aws-iam-no-policy-wildcards — Route53 GetChange/ListHostedZones require wildcard resource
resource "aws_iam_role_policy" "reverse_proxy" {
  name = "${var.app_name}-reverse-proxy-policy"
  role = aws_iam_role.reverse_proxy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CertbotRoute53"
        Effect = "Allow"
        Action = [
          "route53:GetChange",
          "route53:ChangeResourceRecordSets",
          "route53:ListHostedZones",
          "route53:ListResourceRecordSets",
        ]
        Resource = "*"
      },
      {
        Sid    = "CertS3Backup"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "s3:DeleteObject",
        ]
        Resource = [
          "arn:aws:s3:::${var.cert_bucket}",
          "arn:aws:s3:::${var.cert_bucket}/*",
        ]
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

  # Boot sequence:
  # 1. Try to restore cert from S3 (avoids Let's Encrypt rate limit on instance recreate)
  # 2. Run certbot only if cert missing or expires within 30 days
  # 3. After certbot, back up cert to S3
  # 4. Configure Nginx and start
  user_data = <<-EOF
    #!/bin/bash
    set -e

    CERT_BUCKET="${var.cert_bucket}"
    DOMAIN="${var.domain_name}"
    CERT_DIR="/etc/letsencrypt"

    # Install nginx and certbot with Route53 DNS plugin
    dnf install -y nginx python3-pip
    pip3 install certbot certbot-dns-route53

    # Step 1: Restore cert from S3 if available
    echo "Restoring cert from S3..."
    aws s3 sync s3://$CERT_BUCKET/letsencrypt $CERT_DIR --quiet || true

    # Step 2: Check if cert is valid for >30 days; if not, run certbot
    CERT_PATH="$CERT_DIR/live/$DOMAIN/fullchain.pem"
    NEED_CERT=true

    if [ -f "$CERT_PATH" ]; then
      # openssl returns exit 0 if cert expires after the given date
      if openssl x509 -checkend $((30 * 86400)) -noout -in "$CERT_PATH" 2>/dev/null; then
        echo "Cert valid for >30 days, skipping certbot."
        NEED_CERT=false
      else
        echo "Cert missing or expires within 30 days, requesting new cert."
      fi
    fi

    if [ "$NEED_CERT" = "true" ]; then
      certbot certonly \
        --dns-route53 \
        --non-interactive \
        --agree-tos \
        --email ${var.certbot_email} \
        -d $DOMAIN

      # Step 3: Back up new cert to S3
      echo "Backing up cert to S3..."
      aws s3 sync $CERT_DIR s3://$CERT_BUCKET/letsencrypt --quiet
    fi

    # Configure Nginx: HTTP → HTTPS redirect + HTTPS reverse proxy to upstream
    cat > /etc/nginx/conf.d/reverse-proxy.conf <<NGINX
    # Redirect all HTTP to HTTPS
    server {
      listen 80;
      server_name $DOMAIN;
      return 301 https://\$host\$request_uri;
    }

    # HTTPS reverse proxy — terminates SSL, forwards to upstream over HTTP
    server {
      listen 443 ssl;
      server_name $DOMAIN;

      ssl_certificate     $CERT_DIR/live/$DOMAIN/fullchain.pem;
      ssl_certificate_key $CERT_DIR/live/$DOMAIN/privkey.pem;

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

    # Auto-renew cert twice daily and sync back to S3 after renewal
    cat >> /etc/crontab <<CRON
    0 0,12 * * * root certbot renew --quiet --deploy-hook "nginx -s reload && aws s3 sync $CERT_DIR s3://$CERT_BUCKET/letsencrypt --quiet"
    CRON

    systemctl enable nginx
    systemctl start nginx
  EOF

  tags = { Name = "${var.app_name}-reverse-proxy" }
}
