# Output EC2 Instance ID
output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.ec2_instance.id
}

# Output Private IP of EC2
output "private_ip" {
  description = "Private IP address of the EC2 instance"
  value       = aws_instance.ec2_instance.private_ip
}

# Output SSM Session Connection Command
output "ssm_session_command" {
  description = "Command to connect to the instance using AWS SSM Session Manager"
  value = "aws ssm start-session --target ${aws_instance.ec2_instance.id}"
}

# Output Internet Access State
output "internet_access_enabled" {
  description = "Whether outbound internet access is currently enabled for the private subnet"
  value       = var.enable_internet_access
}


