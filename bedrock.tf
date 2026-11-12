# Bedrock foundation models are AWS-managed. This policy grants the workload
# access to approved existing model and inference-profile ARNs; it does not
# provision a model, inference profile, or gateway configuration.
data "aws_iam_policy_document" "ai_gateway_bedrock_inference_permissions" {
  count = var.enable_ai_gateway_pod_identity ? 1 : 0

  statement {
    sid       = "InvokeApprovedModels"
    actions   = concat(["bedrock:InvokeModel"], var.enable_bedrock_streaming ? ["bedrock:InvokeModelWithResponseStream"] : [])
    resources = var.bedrock_model_arns
  }

  dynamic "statement" {
    for_each = length(var.inference_profile_arns) > 0 ? [1] : []
    content {
      sid       = "ReadApprovedInferenceProfiles"
      actions   = ["bedrock:GetInferenceProfile"]
      resources = var.inference_profile_arns
    }
  }
}

resource "aws_iam_role_policy" "ai_gateway_bedrock_inference" {
  count = var.enable_ai_gateway_pod_identity ? 1 : 0

  name   = "invoke-approved-bedrock-models"
  role   = aws_iam_role.ai_gateway_data_plane[0].id
  policy = data.aws_iam_policy_document.ai_gateway_bedrock_inference_permissions[0].json

  lifecycle {
    precondition {
      condition     = length(var.bedrock_model_arns) > 0
      error_message = "Specify at least one approved Bedrock model ARN when Pod Identity is enabled."
    }
    precondition {
      condition     = alltrue([for arn in var.inference_profile_arns : contains(var.bedrock_model_arns, arn)])
      error_message = "Every inference profile ARN must also be present in bedrock_model_arns."
    }
  }
}
