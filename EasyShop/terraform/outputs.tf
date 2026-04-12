# VPC Outputs
output "vpc_id" {
  description = "The ID of the VPC"
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "The CIDR block of the VPC"
  value       = local.vpc_cidr
}

output "public_subnets" {
  description = "List of IDs of public subnets"
  value       = module.vpc.public_subnets
}

output "private_subnets" {
  description = "List of IDs of private subnets"
  value       = module.vpc.private_subnets
}

# EKS Outputs
output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = local.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = module.eks.cluster_endpoint
}

output "cluster_security_group_id" {
  description = "Security group IDs attached to the cluster"
  value       = module.eks.cluster_security_group_id
}

# Bastion Outputs
output "bastion_public_ip" {
  description = "Public IP address of the bastion host"
  value       = module.bastion.bastion_public_ip
}

output "bastion_security_group_id" {
  description = "ID of the bastion security group"
  value       = module.security_group.bastion_security_group_id
}

# Access Information
output "access_information" {
  description = "Access information for the infrastructure"
  value = {
    bastion = {
      public_ip = module.bastion.bastion_public_ip
      ssh_command = "ssh -i ${module.bastion.bastion_key_path} ubuntu@${module.bastion.bastion_public_ip}"
      scp_command = "scp -i ${module.bastion.bastion_key_path} modules/bastion/install-tools.sh ubuntu@${module.bastion.bastion_public_ip}:~/install-tools.sh"
      post_install = "After copying the script, run: chmod +x ~/install-tools.sh && ./install-tools.sh"
    }
    eks = {
      cluster_name = local.cluster_name
      endpoint = module.eks.cluster_endpoint
      kubeconfig_cmd = "aws eks update-kubeconfig --region ${local.region} --name ${local.cluster_name}"
    }
    vpc = {
      id = module.vpc.vpc_id
      cidr = local.vpc_cidr
      public_subnets = module.vpc.public_subnets
      private_subnets = module.vpc.private_subnets
    }
  }
}

# Service URLs
output "service_urls" {
  description = "URLs for accessing services"
  value = {
    argocd     = "https://argocd.letsdeployit.com"
    prometheus = "https://prometheus.letsdeployit.com"
    grafana    = "https://grafana.letsdeployit.com"
    easyshop   = "https://easyshop.letsdeployit.com"
  }
}

# Important Commands
output "important_commands" {
  description = "Important commands for managing the infrastructure"
  value = {
    get_nodes          = "kubectl get nodes"
    get_pods           = "kubectl get pods -A"
    get_services       = "kubectl get services -A"
    get_ingress        = "kubectl get ingress -A"
    get_argocd_password = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
    get_loadbalancer   = "kubectl get service -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
  }
} 