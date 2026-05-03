resource "aws_iam_role" "autoscaler" {
  name = "${var.cluster_name}-cluster-autoscaler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(var.oidc_provider_url, "https://", "")}:aud" = "sts.amazonaws.com"
          "${replace(var.oidc_provider_url, "https://", "")}:sub" = "system:serviceaccount:${var.namespace}:${var.service_account_name}"
        }
      }
    }]
  })

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-autoscaler-role"
  })
}

resource "aws_iam_role_policy_attachment" "autoscaler" {
  role       = aws_iam_role.autoscaler.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterAutoscalerPolicy"
}

resource "kubernetes_service_account" "autoscaler" {
  metadata {
    name      = var.service_account_name
    namespace = var.namespace
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.autoscaler.arn
    }
  }
}
