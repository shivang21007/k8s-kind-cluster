output "security_group_id" {
  description = "The ID of the security group"
  value       = aws_security_group.my-sg.id
}

output "vpc_id" {
  description = "The ID of the VPC"
  value       = data.aws_vpc.my_vpc.id
}

output "instance_public_ips" {
  description = "Public IP addresses of the instances"
  value       = { for i, inst in aws_instance.control-plane : var.instance_names[i] => inst.public_ip }
}

output "instance_private_ips" {
  description = "Private IP addresses of the instances"
  value       = { for i, inst in aws_instance.control-plane : var.instance_names[i] => inst.private_ip }
}

output "instance_public_dns" {
  description = "Public DNS names of the instances"
  value       = { for i, inst in aws_instance.control-plane : var.instance_names[i] => inst.public_dns }
}