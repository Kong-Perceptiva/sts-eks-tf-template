variable "aws_account_id" {
  description = "Expected 12-digit AWS account ID; prevents deployment to a different account."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "Provide a 12-digit AWS account ID."
  }
}

variable "aws_region" {
  description = "AWS region for the VPC, EKS cluster, and the Bedrock requests."
  type        = string
}

variable "environment" {
  description = "Environment identifier used for tags, such as nonprod."
  type        = string
}

variable "cluster_name" {
  description = "Unique EKS cluster name in this account and region."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9-]{0,34}$", var.cluster_name))
    error_message = "Use 1-35 letters, digits, or hyphens; start with a letter."
  }
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version approved and supported by the customer and gateway components."
  type        = string
}

variable "vpc_cidr" {
  description = "Non-overlapping IPv4 VPC CIDR approved by the network team."
  type        = string
}

variable "availability_zones" {
  description = "At least two approved availability zones in the selected AWS region."
  type        = list(string)

  validation {
    condition     = length(distinct(var.availability_zones)) >= 2
    error_message = "Provide at least two distinct availability zones."
  }
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs, one per availability zone, for EKS workloads."
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs, one per availability zone, for NAT gateways."
  type        = list(string)
}

variable "single_nat_gateway" {
  description = "Use one NAT gateway for a lower-cost lab; false creates one per AZ. Not an HA setting when true."
  type        = bool
  default     = false
}

variable "endpoint_public_access_cidrs" {
  description = "Approved IPv4 CIDRs for the public Kubernetes API endpoint; use an empty list with private-only access."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for cidr in var.endpoint_public_access_cidrs : can(cidrnetmask(cidr)) && cidr != "0.0.0.0/0"])
    error_message = "Provide valid IPv4 CIDRs without 0.0.0.0/0."
  }
}

variable "enable_cluster_creator_admin_permissions" {
  description = "Grant cluster admin to the Terraform caller; enable only when approved."
  type        = bool
  default     = false
}

variable "cluster_admin_principal_arns" {
  description = "IAM role or user ARNs to grant cluster-admin access through EKS access entries."
  type        = set(string)
  default     = []
}

variable "enable_ai_gateway_pod_identity" {
  description = "Create the AI Gateway data plane IAM role and EKS Pod Identity association, including approved Bedrock permissions."
  type        = bool
  default     = false
}

variable "ai_gateway_data_plane_namespace" {
  description = "Kubernetes namespace containing the AI Gateway data plane ServiceAccount."
  type        = string
  default     = "kong"
}

variable "ai_gateway_data_plane_service_account" {
  description = "Kubernetes ServiceAccount used by the AI Gateway data plane pods."
  type        = string
  default     = "kong-dp"
}

variable "bedrock_model_arns" {
  description = "Explicit approved foundation-model or inference-profile ARNs for invocation; never use a wildcard."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for arn in var.bedrock_model_arns : can(regex("^arn:[a-z0-9-]+:bedrock:[a-z0-9-]+:[0-9]*:(foundation-model|inference-profile|application-inference-profile)/[^*?]+$", arn))])
    error_message = "Use explicit Bedrock foundation-model or inference-profile ARNs without wildcards."
  }
}

variable "enable_bedrock_streaming" {
  description = "Allow InvokeModelWithResponseStream in addition to non-streaming inference."
  type        = bool
  default     = true
}

variable "inference_profile_arns" {
  description = "Explicit inference profile ARNs requiring GetInferenceProfile; include the same profiles in bedrock_model_arns."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for arn in var.inference_profile_arns : can(regex("^arn:[a-z0-9-]+:bedrock:[a-z0-9-]+:[0-9]*:(inference-profile|application-inference-profile)/[^*?]+$", arn))])
    error_message = "Use explicit Bedrock inference profile ARNs without wildcards."
  }
}

variable "secrets_manager_secrets" {
  description = "Optional Secrets Manager secret containers. Terraform creates metadata only, never secret values. Requires enable_ai_gateway_pod_identity."
  type = map(object({
    name                    = string
    description             = optional(string, "Managed secret for the data plane")
    kms_key_arn             = optional(string)
    recovery_window_in_days = optional(number, 30)
  }))
  default = {}

  validation {
    condition     = alltrue([for secret in values(var.secrets_manager_secrets) : length(trimspace(secret.name)) > 0 && secret.recovery_window_in_days >= 7 && secret.recovery_window_in_days <= 30 && floor(secret.recovery_window_in_days) == secret.recovery_window_in_days])
    error_message = "Provide non-empty secret names and an integer recovery window between 7 and 30 days."
  }

  validation {
    condition     = alltrue([for secret in values(var.secrets_manager_secrets) : secret.kms_key_arn == null ? true : can(regex("^arn:[a-z0-9-]+:kms:[a-z0-9-]+:[0-9]{12}:key/[^*?]+$", secret.kms_key_arn))])
    error_message = "Use a full customer-managed KMS key ARN without wildcards, or omit kms_key_arn."
  }

  validation {
    condition     = length(distinct([for secret in values(var.secrets_manager_secrets) : secret.name])) == length(var.secrets_manager_secrets)
    error_message = "Each secret name must be unique."
  }
}

variable "secrets_manager_read_prefix" {
  description = "Optional approved Secrets Manager name prefix ending in '/', allowing the workload to read existing and future matching secrets in this account and region."
  type        = string
  default     = null

  validation {
    condition     = var.secrets_manager_read_prefix == null ? true : can(regex("^[A-Za-z0-9][A-Za-z0-9/_+=.@-]*/$", var.secrets_manager_read_prefix))
    error_message = "Use a non-empty secret name prefix ending in '/', without IAM wildcards."
  }
}

variable "secrets_manager_prefix_kms_key_arns" {
  description = "Optional customer-managed KMS key ARNs for prefix-scoped secrets in the selected account and region."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for arn in var.secrets_manager_prefix_kms_key_arns : can(regex("^arn:[a-z0-9-]+:kms:[a-z0-9-]+:[0-9]{12}:key/[^*?]+$", arn))])
    error_message = "Use full customer-managed KMS key ARNs without wildcards."
  }
}

variable "tags" {
  description = "Additional non-sensitive tags required by the customer."
  type        = map(string)
  default     = {}
}
