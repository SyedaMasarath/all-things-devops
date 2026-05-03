# Secrets that MUST be configured in GitHub Repository Settings

## AWS Secrets (using OIDC — no long-lived keys needed)
AWS_ACCOUNT_ID=123456789012
AWS_PLAN_ROLE_ARN=arn:aws:iam::123456789012:role/github-actions-tf-plan
AWS_APPLY_ROLE_ARN_DEV=arn:aws:iam::123456789012:role/github-actions-tf-apply-dev
AWS_APPLY_ROLE_ARN_PROD=arn:aws:iam::123456789012:role/github-actions-tf-apply-prod
AWS_DEPLOY_ROLE_ARN_DEV=arn:aws:iam::123456789012:role/github-actions-deploy-dev
AWS_DEPLOY_ROLE_ARN_PROD=arn:aws:iam::123456789012:role/github-actions-deploy-prod
AWS_ECR_PUSH_ROLE_ARN=arn:aws:iam::123456789012:role/github-actions-ecr-push

## Notifications
SLACK_BOT_TOKEN=xoxb-...
SLACK_CHANNEL_ID=C0123456789
SLACK_DEPLOY_CHANNEL_ID=C9876543210

## Optional integrations
INFRACOST_API_KEY=ico-...
CODECOV_TOKEN=...
GITHUB_CLIENT_ID=...         # For Grafana SSO
GITHUB_CLIENT_SECRET=...     # For Grafana SSO

---

# IAM Role Trust Policy for GitHub Actions OIDC
# Apply this policy to each github-actions-* IAM role

{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:YOUR-ORG/aws-eks-platform:*"
        }
      }
    }
  ]
}
