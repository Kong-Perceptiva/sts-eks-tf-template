output "eks_cluster_name" {
  description = "EKS cluster name."
  value       = module.ai_gateway_eks_auto.cluster_name
}

output "eks_cluster_api_endpoint" {
  description = "Kubernetes API endpoint; reachability depends on VPC and endpoint settings."
  value       = module.ai_gateway_eks_auto.cluster_endpoint
}

output "ai_gateway_vpc_id" {
  description = "VPC containing the cluster."
  value       = module.ai_gateway_vpc.vpc_id
}

output "eks_workload_private_subnet_ids" {
  description = "Private subnet IDs for EKS workloads."
  value       = module.ai_gateway_vpc.private_subnets
}

output "ai_gateway_data_plane_role_arn" {
  description = "Pod Identity IAM role ARN, or null when the optional identity is disabled."
  value       = try(aws_iam_role.ai_gateway_data_plane[0].arn, null)
}

output "ai_gateway_pod_identity_association_id" {
  description = "EKS Pod Identity association ID, or null when disabled."
  value       = try(aws_eks_pod_identity_association.ai_gateway_data_plane[0].association_id, null)
}

output "secrets_manager_secret_arns" {
  description = "ARNs of the optional Secrets Manager containers; values are not managed by Terraform."
  value       = { for key, secret in aws_secretsmanager_secret.ai_gateway_secret_container : key => secret.arn }
}
