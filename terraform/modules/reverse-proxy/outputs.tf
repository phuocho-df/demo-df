output "public_ip" {
  description = "Public IP address of the reverse proxy instance"
  value       = aws_instance.reverse_proxy.public_ip
}

output "instance_id" {
  description = "EC2 instance ID of the reverse proxy"
  value       = aws_instance.reverse_proxy.id
}
