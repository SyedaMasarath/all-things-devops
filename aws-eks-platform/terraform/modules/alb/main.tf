resource "aws_iam_role" "alb" {
  name = "${var.cluster_name}-alb-controller-role"

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
    Name = "${var.cluster_name}-alb-controller-role"
  })
}

resource "aws_iam_role_policy_attachment" "alb" {
  role       = aws_iam_role.alb.name
  policy_arn = "arn:aws:iam::aws:policy/AWSLoadBalancerControllerIAMPolicy"
}

resource "kubernetes_service_account" "alb" {
  metadata {
    name      = var.service_account_name
    namespace = var.namespace
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.alb.arn
    }
  }
}
