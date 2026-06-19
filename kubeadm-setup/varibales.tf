
variable "aws_region" {
  description = "The AWS region to deploy the cluster to"
  type        = string
  default     = "ap-south-1"
}

variable "aws_ami_id" {
  description = "The AWS AMI ID to deploy the cluster to"
  type        = string
  default     = "ami-006f82a1d5a27da54"

  // ami-006f82a1d5a27da54 -> for ubuntu 24.04 in ap-south-1
  //ami-0f8a61b66d1accaee -> for ubuntu 24.04 in us-east-1
}

variable "aws_instance_type" {
  description = "The AWS instance type to deploy the cluster to"
  type        = string
  default     = "c7i-flex.large"

  // c7i-flex.large -> 2vcpu , 4gb memory
  // m7i-flex.large -> 2vcpu , 8gb memory
}

variable "aws_root_block_device_size" {
  description = "The size of the root block device"
  type        = number
  default     = 10
}

variable "instance_count" {
  description = "The number of instances to deploy"
  type        = number
  default     = 3
}

variable "instance_names" {
  description = "The names of the instances to deploy"
  type        = list(string)
  default     = ["control-plane", "worker-01", "worker-02"]
}