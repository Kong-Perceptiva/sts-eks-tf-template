locals {
  eks_cluster_admin_access_entries = {
    for arn in var.cluster_admin_principal_arns : arn => {
      principal_arn = arn
      policy_associations = {
        cluster_admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }
}

module "ai_gateway_eks_auto" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.29.0"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version
  vpc_id             = module.ai_gateway_vpc.vpc_id
  subnet_ids         = module.ai_gateway_vpc.private_subnets

  authentication_mode                      = "API"
  enable_cluster_creator_admin_permissions = var.enable_cluster_creator_admin_permissions
  access_entries                           = local.eks_cluster_admin_access_entries

  # Private API access is always enabled; public access requires explicit CIDRs.
  endpoint_private_access      = true
  endpoint_public_access       = length(var.endpoint_public_access_cidrs) > 0
  endpoint_public_access_cidrs = var.endpoint_public_access_cidrs

  compute_config = {
    enabled    = true
    node_pools = ["general-purpose", "system"]
  }

  # EKS Auto Mode includes Pod Identity; no IRSA OIDC provider is needed here.
  enable_irsa                              = false
  enable_auto_mode_block_storage_policy_v2 = true

  iam_role_name                 = "${var.cluster_name}-cluster"
  iam_role_use_name_prefix      = false
  node_iam_role_name            = "${var.cluster_name}-node"
  node_iam_role_use_name_prefix = false

  depends_on = [terraform_data.infrastructure_input_validation]
}

resource "terraform_data" "infrastructure_input_validation" {
  input = "validate"

  lifecycle {
    precondition {
      condition     = length(var.private_subnet_cidrs) == length(var.availability_zones) && length(var.public_subnet_cidrs) == length(var.availability_zones)
      error_message = "Supply one private and one public subnet CIDR per availability zone."
    }
    precondition {
      condition     = var.enable_cluster_creator_admin_permissions || length(var.cluster_admin_principal_arns) > 0
      error_message = "Specify an approved cluster admin principal or explicitly enable creator admin access."
    }
    precondition {
      condition     = (length(var.secrets_manager_secrets) == 0 && var.secrets_manager_read_prefix == null && length(var.secrets_manager_prefix_kms_key_arns) == 0) || var.enable_ai_gateway_pod_identity
      error_message = "Secrets Manager access requires enable_ai_gateway_pod_identity so the data plane IAM role exists."
    }
    precondition {
      condition     = length(var.secrets_manager_prefix_kms_key_arns) == 0 || var.secrets_manager_read_prefix != null
      error_message = "Prefix KMS keys require a configured Secrets Manager read prefix."
    }
    precondition {
      condition     = alltrue([for arn in var.secrets_manager_prefix_kms_key_arns : try(split(":", arn)[3] == var.aws_region && split(":", arn)[4] == var.aws_account_id, false)])
      error_message = "Prefix KMS keys must belong to the selected AWS account and region."
    }
  }
}
