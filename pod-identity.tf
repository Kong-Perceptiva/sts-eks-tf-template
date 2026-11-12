data "aws_iam_policy_document" "ai_gateway_data_plane_pod_identity_trust" {
  count = var.enable_ai_gateway_pod_identity ? 1 : 0

  statement {
    sid     = "AllowScopedEKSPodIdentity"
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }

    # These conditions depend on EKS Pod Identity session tags remaining enabled.
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/eks-cluster-arn"
      values   = [module.ai_gateway_eks_auto.cluster_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/kubernetes-namespace"
      values   = [var.ai_gateway_data_plane_namespace]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/kubernetes-service-account"
      values   = [var.ai_gateway_data_plane_service_account]
    }
  }
}

resource "aws_iam_role" "ai_gateway_data_plane" {
  count = var.enable_ai_gateway_pod_identity ? 1 : 0

  name               = "${var.cluster_name}-ai-gateway-dp"
  description        = "Allows the data plane to use approved Bedrock models and optional secrets."
  assume_role_policy = data.aws_iam_policy_document.ai_gateway_data_plane_pod_identity_trust[0].json
}

resource "aws_eks_pod_identity_association" "ai_gateway_data_plane" {
  count = var.enable_ai_gateway_pod_identity ? 1 : 0

  cluster_name         = module.ai_gateway_eks_auto.cluster_name
  namespace            = var.ai_gateway_data_plane_namespace
  service_account      = var.ai_gateway_data_plane_service_account
  role_arn             = aws_iam_role.ai_gateway_data_plane[0].arn
  disable_session_tags = false

  depends_on = [aws_iam_role_policy.ai_gateway_bedrock_inference, aws_iam_role_policy.ai_gateway_secrets_manager_read]
}
