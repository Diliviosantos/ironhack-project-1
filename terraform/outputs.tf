output "public_instance_ip" {
  description = "Public IP address of the public EC2 instance."
  value       = aws_instance.ec2-pub.public_ip
}
output "private_instance_B_ip" {
  description = "IP address of the private EC2 instance."
  value       = aws_instance.ec2-private.public_ip
}

output "private_instance_c_ip" {
  description = "ip address of the private instance."
  value       = aws_instance.ec2-private-C.public_ip
}