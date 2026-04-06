output "public_ip" {
  description = "Elastic IP address of the reverse proxy (static, use for Route53)"
  value       = aws_eip.reverse_proxy.public_ip
}

output "instance_id" {
  description = "EC2 instance ID of the reverse proxy"
  value       = aws_instance.reverse_proxy.id
}
