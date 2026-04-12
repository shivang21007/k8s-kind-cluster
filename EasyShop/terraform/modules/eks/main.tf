module "eks" {

  source  = "terraform-aws-modules/eks/aws"
  version = "19.15.1"

  cluster_name                   = var.cluster_name
  cluster_version                = var.cluster_version
  cluster_endpoint_public_access = true
  cluster_endpoint_private_access = true
  cluster_addons = {
    coredns = {
      most_recent = false
      version     = var.eks_addon_versions.coredns
    }
    kube-proxy = {
      most_recent = false
      version     = var.eks_addon_versions.kube-proxy
    }
    vpc-cni = {
      most_recent = false
      version     = var.eks_addon_versions.vpc-cni
    }
    aws-ebs-csi-driver = {
      most_recent = false
      version     = var.eks_addon_versions.aws-ebs-csi-driver
    }
  }

  vpc_id                   = var.vpc_id
  subnet_ids               = var.subnet_ids
  control_plane_subnet_ids = var.control_plane_subnet_ids

  # EKS Managed Node Group(s)
  eks_managed_node_group_defaults = {
    ami_type       = "AL2023_x86_64_STANDARD"
    instance_types = ["t3.medium"]
    disk_size      = 50
    disk_type      = "gp3"
    iops           = 3000
    throughput     = 125
  }


  eks_managed_node_groups = {
    easyshop-node-group = {
      min_size     = 2
      max_size     = 3
      desired_size = 2
      instance_types = ["t3.medium", "t2.medium"]
      capacity_type  = "SPOT"
      iam_role_additional_policies = {
        AmazonEBSCSIDriverPolicy = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
        AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
      }
      tags = {
        Project     = "EasyShop"
        Environment = var.environment
        NodeGroup   = "easyshop-workers"
      }
    }
  }

  cluster_security_group_additional_rules = {
    ingress_bastion_443 = {
      description              = "Bastion to EKS API"
      protocol                 = "tcp"
      from_port                = 443
      to_port                  = 443
      type                     = "ingress"
      source_security_group_id = var.bastion_security_group_id
    }
    
    ingress_nodes_443 = {
      description              = "Nodes to cluster API"
      protocol                 = "tcp"
      from_port                = 443
      to_port                  = 443
      type                     = "ingress"
      source_security_group_id = module.eks.node_security_group_id
    }
    
    ingress_load_balancer_443 = {
      description = "Load balancer to cluster API"
      protocol    = "tcp"
      from_port   = 443
      to_port     = 443
      type        = "ingress"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  node_security_group_additional_rules = {
    ingress_bastion_ssh = {
      description              = "Bastion to nodes SSH"
      protocol                 = "tcp"
      from_port                = 22
      to_port                  = 22
      type                     = "ingress"
      source_security_group_id = var.bastion_security_group_id
    }
    
    ingress_bastion_kubelet = {
      description              = "Bastion to nodes kubelet API"
      protocol                 = "tcp"
      from_port                = 10250
      to_port                  = 10250
      type                     = "ingress"
      source_security_group_id = var.bastion_security_group_id
    }
    
    ingress_cluster_kubelet = {
      description              = "Cluster to nodes kubelet API"
      protocol                 = "tcp"
      from_port                = 10250
      to_port                  = 10250
      type                     = "ingress"
      source_security_group_id = module.eks.cluster_security_group_id
    }
    
    ingress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
    
    egress_all = {
      description      = "Node all egress"
      protocol         = "-1"
      from_port        = 0
      to_port          = 0
      type             = "egress"
      cidr_blocks      = ["0.0.0.0/0"]
    }
  }

  tags = var.tags
}
