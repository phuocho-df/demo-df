output "public_ip" {
  description = "Public IP address of the bastion host"
  value       = aws_instance.bastion.public_ip
}

output "instance_id" {
  description = "EC2 instance ID of the bastion host"
  value       = aws_instance.bastion.id
}
