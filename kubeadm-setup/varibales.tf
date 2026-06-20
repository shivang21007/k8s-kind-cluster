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
  default     = "t3.small"

  // c7i-flex.large -> 2vcpu , 4gb memory 0.08479 usd/hour
  // m7i-flex.large -> 2vcpu , 8gb memory 0.10075 usd/hour
  // m7i-flex.xlarge -> 4vcpu , 16gb memory 0.1815 usd/hour
  // m7i-flex.2xlarge -> 8vcpu , 32gb memory 0.3584 usd/hour
  // m7i-flex.4xlarge -> 16vcpu , 64gb memory 0.7168 usd/hour
  // m7i-flex.8xlarge -> 32vcpu , 128gb memory 1.4336 usd/hour
  // t3.micro -> 2vcpu , 1gb memory 0.0112 usd/hour
  // t3.small -> 2vcpu , 2gb memory 0.0224 usd/hour
  // t3.medium -> 2vcpu , 4gb memory 0.0448 usd/hour
  // t3.large -> 2vcpu , 8gb memory 0.0896 usd/hour
  // t3.xlarge -> 4vcpu , 16gb memory 0.1792 usd/hour
  // t3.2xlarge -> 8vcpu , 32gb memory 0.3584 usd/hour
  // t3.4xlarge -> 16vcpu , 64gb memory 0.7168 usd/hour
  // t3.8xlarge -> 32vcpu , 128gb memory 1.4336 usd/hour
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
  default     = ["control-plane-01", "worker-01", "worker-02"]
}