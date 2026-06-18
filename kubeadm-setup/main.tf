provider "aws" {
  region = "us-east-1"
}


resource "aws_key_pair" "my-key" {
  key_name   = "terraform-key.pem.pub"
  public_key = file("./keys/terraform-key.pem.pub")
}

data "aws_vpc" "my_vpc" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.my_vpc.id]
  }
}

locals {
  instance_names = ["control-plane", "worker-01", "worker-02"]
}

resource "aws_security_group" "my-sg" {
  vpc_id      = data.aws_vpc.my_vpc.id
  name        = "my-sg"
  description = "Security group for EC2 instances"

  ingress {
    description = "for kubeapiserver etcd"
    from_port   = 2379
    to_port     = 2380
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.my_vpc.cidr_block]
  }

  ingress {
    description = "BGP TCP 179"
    from_port   = 179
    to_port     = 179
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "for kube scheduler, kubeletapi, control-manager"
    from_port   = 10249
    to_port     = 10260
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.my_vpc.cidr_block]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Typha TCP 5473"
    from_port   = 5473
    to_port     = 5473
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "api-server"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "nodeport services"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "UDP 4789 bidirectional between all nodes"
    from_port   = 4789
    to_port     = 4789
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "control-plane" {
  count           = 3
  ami             = "ami-0f8a61b66d1accaee"
  instance_type   = "c7i-flex.large"
  key_name        = aws_key_pair.my-key.key_name
  vpc_security_group_ids = [aws_security_group.my-sg.id]
  subnet_id       = data.aws_subnets.default.ids[0]
  source_dest_check = false

  root_block_device {
    volume_size = 10
  }

  tags = {
    Name = local.instance_names[count.index]
  }

}

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
  value       = { for i, inst in aws_instance.control-plane : local.instance_names[i] => inst.public_ip }
}

output "instance_private_ips" {
  description = "Private IP addresses of the instances"
  value       = { for i, inst in aws_instance.control-plane : local.instance_names[i] => inst.private_ip }
}

output "instance_public_dns" {
  description = "Public DNS names of the instances"
  value       = { for i, inst in aws_instance.control-plane : local.instance_names[i] => inst.public_dns }
}