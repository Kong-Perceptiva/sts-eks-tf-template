data "aws_partition" "current" {}

# Secret values and versions are deliberately managed outside Terraform.
resource "aws_secretsmanager_secret" "ai_gateway_secret_container" {
  for_each = var.secrets_manager_secrets

  name                    = each.value.name
  description             = each.value.description
  kms_key_id              = each.value.kms_key_arn
  recovery_window_in_days = each.value.recovery_window_in_days

  lifecycle {
    precondition {
      condition     = each.value.kms_key_arn == null ? true : try(split(":", each.value.kms_key_arn)[3] == var.aws_region && split(":", each.value.kms_key_arn)[4] == var.aws_account_id, false)
      error_message = "The customer-managed KMS key must belong to the selected AWS account and region."
    }
  }
}

locals {
  ai_gateway_secrets_manager_prefix_arn  = var.secrets_manager_read_prefix == null ? null : "arn:${data.aws_partition.current.partition}:secretsmanager:${var.aws_region}:${var.aws_account_id}:secret:${var.secrets_manager_read_prefix}*"
  enable_ai_gateway_secrets_manager_read = var.enable_ai_gateway_pod_identity && (length(var.secrets_manager_secrets) > 0 || var.secrets_manager_read_prefix != null)
}

data "aws_iam_policy_document" "ai_gateway_secrets_manager_read_permissions" {
  count = local.enable_ai_gateway_secrets_manager_read ? 1 : 0

  statement {
    sid     = "ReadApprovedSecrets"
    actions = ["secretsmanager:GetSecretValue"]
    resources = concat(
      [for secret in aws_secretsmanager_secret.ai_gateway_secret_container : secret.arn],
      local.ai_gateway_secrets_manager_prefix_arn == null ? [] : [local.ai_gateway_secrets_manager_prefix_arn],
    )
  }

  # Customer-managed keys also need a compatible key policy or grant.
  dynamic "statement" {
    for_each = { for key, secret in var.secrets_manager_secrets : key => secret if secret.kms_key_arn != null }
    content {
      actions   = ["kms:Decrypt"]
      resources = [statement.value.kms_key_arn]

      condition {
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = ["secretsmanager.${var.aws_region}.${data.aws_partition.current.dns_suffix}"]
      }
      condition {
        test     = "StringEquals"
        variable = "kms:EncryptionContext:SecretARN"
        values   = [aws_secretsmanager_secret.ai_gateway_secret_container[statement.key].arn]
      }
    }
  }

  dynamic "statement" {
    for_each = var.secrets_manager_prefix_kms_key_arns
    content {
      actions   = ["kms:Decrypt"]
      resources = [statement.value]

      condition {
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = ["secretsmanager.${var.aws_region}.${data.aws_partition.current.dns_suffix}"]
      }
      condition {
        test     = "StringLike"
        variable = "kms:EncryptionContext:SecretARN"
        values   = [local.ai_gateway_secrets_manager_prefix_arn]
      }
    }
  }
}

resource "aws_iam_role_policy" "ai_gateway_secrets_manager_read" {
  count = local.enable_ai_gateway_secrets_manager_read ? 1 : 0

  name   = "read-approved-secrets"
  role   = aws_iam_role.ai_gateway_data_plane[0].id
  policy = data.aws_iam_policy_document.ai_gateway_secrets_manager_read_permissions[0].json
}
