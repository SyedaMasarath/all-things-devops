#!/usr/bin/env bash
# =============================================================================
# Bootstrap Script — Initialize Terraform Remote State
# Creates S3 buckets, optional DynamoDB lock tables, and GitHub OIDC provider.
# Supports environment-specific AWS accounts, profiles, and backend names.
# =============================================================================
set -euo pipefail

# Color output
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

usage() {
  cat <<EOF
Usage: $0 [dev|prod|all]

Bootstrap Terraform remote state for one or both environments.
If dev and prod run in different AWS accounts, set environment variables for each.

Environment variables:
  AWS_PROFILE_DEV       AWS CLI profile for dev account
  AWS_PROFILE_PROD      AWS CLI profile for prod account
  AWS_PROFILE           fallback AWS CLI profile

  AWS_REGION_DEV        AWS region for dev
  AWS_REGION_PROD       AWS region for prod
  AWS_REGION            fallback AWS region

  AWS_ACCOUNT_ID_DEV    optional AWS account ID for dev
  AWS_ACCOUNT_ID_PROD   optional AWS account ID for prod
  AWS_ACCOUNT_ID        optional fallback AWS account ID

  TFSTATE_BUCKET_DEV    S3 bucket name for dev state
  TFSTATE_BUCKET_PROD   S3 bucket name for prod state
  TFSTATE_LOCK_TABLE    DynamoDB lock table name
  TFSTATE_KMS_ALIAS     KMS alias for state bucket encryption

Note: this script prefers AWS CLI credentials and STS for account resolution; hardcoding account IDs is not required.
EOF
  exit 1
}

BOOTSTRAP_ENV="${1:-all}"
case "${BOOTSTRAP_ENV}" in
  all|dev|prod) ;;
  *) usage ;;
esac

PROJECT_NAME="eks-platform"
TFSTATE_BUCKET_DEV="${TFSTATE_BUCKET_DEV:-${PROJECT_NAME}-tfstate-dev}"
TFSTATE_BUCKET_PROD="${TFSTATE_BUCKET_PROD:-${PROJECT_NAME}-tfstate-prod}"
TFSTATE_LOCK_TABLE="${TFSTATE_LOCK_TABLE:-${PROJECT_NAME}-tfstate-lock}"
TFSTATE_KMS_ALIAS="${TFSTATE_KMS_ALIAS:-alias/${PROJECT_NAME}-tfstate}"

AWS_PROFILE_DEV="${AWS_PROFILE_DEV:-${AWS_PROFILE:-}}"
AWS_PROFILE_PROD="${AWS_PROFILE_PROD:-${AWS_PROFILE:-}}"
AWS_REGION_DEV="${AWS_REGION_DEV:-${AWS_REGION:-us-east-1}}"
AWS_REGION_PROD="${AWS_REGION_PROD:-${AWS_REGION:-us-east-1}}"
AWS_ACCOUNT_ID_DEV="${AWS_ACCOUNT_ID_DEV:-${AWS_ACCOUNT_ID:-}}"
AWS_ACCOUNT_ID_PROD="${AWS_ACCOUNT_ID_PROD:-${AWS_ACCOUNT_ID:-}}"

# --- Validate prerequisites ---
command -v aws &>/dev/null      || error "aws-cli is not installed"
command -v terraform &>/dev/null || error "terraform is not installed"
command -v openssl &>/dev/null  || error "openssl is not installed"

aws_cmd() {
  local profile="$1"
  shift
  if [ -n "${profile}" ]; then
    aws --profile "${profile}" "$@"
  else
    aws "$@"
  fi
}

resolve_account_id() {
  local env="$1"
  local account_id
  local profile

  if [ "${env}" = "dev" ]; then
    account_id="${AWS_ACCOUNT_ID_DEV}"
    profile="${AWS_PROFILE_DEV}"
  else
    account_id="${AWS_ACCOUNT_ID_PROD}"
    profile="${AWS_PROFILE_PROD}"
  fi

  if [ -n "${account_id}" ]; then
    echo "${account_id}"
    return
  fi

  aws_cmd "${profile}" sts get-caller-identity --query Account --output text
}

resolve_region() {
  local env="$1"
  if [ "${env}" = "dev" ]; then
    echo "${AWS_REGION_DEV}"
  else
    echo "${AWS_REGION_PROD}"
  fi
}

resolve_profile() {
  local env="$1"
  if [ "${env}" = "dev" ]; then
    echo "${AWS_PROFILE_DEV}"
  else
    echo "${AWS_PROFILE_PROD}"
  fi
}

resolve_bucket_name() {
  local env="$1"
  if [ "${env}" = "dev" ]; then
    echo "${TFSTATE_BUCKET_DEV}"
  else
    echo "${TFSTATE_BUCKET_PROD}"
  fi
}

bootstrap_env() {
  local env="$1"
  local profile
  local region
  local bucket_name
  local account_id
  local lock_table
  local kms_alias

  profile="$(resolve_profile "${env}")"
  region="$(resolve_region "${env}")"
  bucket_name="$(resolve_bucket_name "${env}")"
  account_id="$(resolve_account_id "${env}")"
  lock_table="${TFSTATE_LOCK_TABLE}"
  kms_alias="${TFSTATE_KMS_ALIAS}"

  info "Bootstrapping Terraform remote state for ${env}..."
  info "Account: ${account_id:-(from current AWS credentials)}"
  info "Region:  ${region}"
  info "Bucket:  ${bucket_name}"
  info "Profile: ${profile:-(default)}"

  if [ -z "${account_id}" ]; then
    account_id="$(aws_cmd "${profile}" sts get-caller-identity --query Account --output text)"
  fi

  info "Ensuring KMS alias ${kms_alias} exists in ${env}..."
  local kms_key_id
  kms_key_id=$(aws_cmd "${profile}" kms list-aliases --region "${region}" --query "Aliases[?AliasName=='${kms_alias}'].TargetKeyId | [0]" --output text 2>/dev/null || true)
  if [ -z "${kms_key_id}" ] || [ "${kms_key_id}" = "None" ]; then
    kms_key_id=$(aws_cmd "${profile}" kms create-key \
      --description "Terraform state encryption for ${PROJECT_NAME} (${env})" \
      --region "${region}" \
      --query 'KeyMetadata.KeyId' \
      --output text)

    aws_cmd "${profile}" kms create-alias \
      --alias-name "${kms_alias}" \
      --target-key-id "${kms_key_id}" \
      --region "${region}"

    info "KMS alias created: ${kms_alias}"
  else
    info "KMS alias already exists: ${kms_alias}"
  fi

  if aws_cmd "${profile}" s3api head-bucket --bucket "${bucket_name}" --region "${region}" 2>/dev/null; then
    warning "S3 bucket already exists: ${bucket_name}"
  else
    info "Creating S3 bucket: ${bucket_name}..."
    if [ "${region}" = "us-east-1" ]; then
      aws_cmd "${profile}" s3api create-bucket \
        --bucket "${bucket_name}" \
        --region "${region}"
    else
      aws_cmd "${profile}" s3api create-bucket \
        --bucket "${bucket_name}" \
        --region "${region}" \
        --create-bucket-configuration LocationConstraint="${region}"
    fi
    info "S3 bucket created: ${bucket_name}"
  fi

  aws_cmd "${profile}" s3api put-bucket-versioning \
    --bucket "${bucket_name}" \
    --versioning-configuration Status=Enabled

  aws_cmd "${profile}" s3api put-bucket-encryption \
    --bucket "${bucket_name}" \
    --server-side-encryption-configuration '{
      "Rules": [{
        "ApplyServerSideEncryptionByDefault": {
          "SSEAlgorithm": "aws:kms",
          "KMSMasterKeyID": "'"${kms_alias}"'"
        },
        "BucketKeyEnabled": true
      }]
    }'

  aws_cmd "${profile}" s3api put-public-access-block \
    --bucket "${bucket_name}" \
    --public-access-block-configuration \
      BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

  aws_cmd "${profile}" s3api put-bucket-lifecycle-configuration \
    --bucket "${bucket_name}" \
    --lifecycle-configuration '{
      "Rules": [{
        "ID": "expire-old-state-versions",
        "Status": "Enabled",
        "NoncurrentVersionExpiration": {"NoncurrentDays": 90}
      }]
    }'

  info "S3 bucket configured with versioning, encryption, and lifecycle policy"

  info "Creating DynamoDB table: ${lock_table}..."
  if aws_cmd "${profile}" dynamodb describe-table --table-name "${lock_table}" --region "${region}" 2>/dev/null; then
    warning "DynamoDB table already exists: ${lock_table}"
  else
    aws_cmd "${profile}" dynamodb create-table \
      --table-name "${lock_table}" \
      --attribute-definitions AttributeName=LockID,AttributeType=S \
      --key-schema AttributeName=LockID,KeyType=HASH \
      --billing-mode PAY_PER_REQUEST \
      --sse-specification Enabled=true \
      --region "${region}"

    aws_cmd "${profile}" dynamodb wait table-exists \
      --table-name "${lock_table}" \
      --region "${region}"

    info "DynamoDB table created: ${lock_table}"
  fi

  info "Setting up GitHub Actions OIDC provider in ${env} account..."
  local oidc_arn
  oidc_arn=$(aws_cmd "${profile}" iam list-open-id-connect-providers \
    --query 'OpenIDConnectProviderList[?ends_with(Arn, `token.actions.githubusercontent.com`)].Arn' \
    --output text)

  if [ -z "${oidc_arn}" ]; then
    local thumbprint
    thumbprint=$(echo | openssl s_client -connect token.actions.githubusercontent.com:443 2>/dev/null \
      | openssl x509 -fingerprint -sha1 -noout 2>/dev/null \
      | sed 's/SHA1 Fingerprint=//' | tr -d ':' | tr '[:upper:]' '[:lower:]')

    aws_cmd "${profile}" iam create-open-id-connect-provider \
      --url https://token.actions.githubusercontent.com \
      --client-id-list sts.amazonaws.com \
      --thumbprint-list "${thumbprint}"

    info "GitHub Actions OIDC provider created in ${env} account"
  else
    info "GitHub Actions OIDC provider already exists in ${env} account: ${oidc_arn}"
  fi

  echo ""
  echo "Backend config for ${env}:"
  echo "  bucket         = \"${bucket_name}\""
  echo "  key            = \"${env}/terraform.tfstate\""
  echo "  region         = \"${region}\""
  echo "  encrypt        = true"
  echo "  dynamodb_table = \"${lock_table}\""
  echo "  kms_key_id     = \"${kms_alias}\""
  echo ""
}

info "Bootstrapping Terraform remote state..."
case "${BOOTSTRAP_ENV}" in
  all)
    bootstrap_env dev
    bootstrap_env prod
    ;;
  dev)
    bootstrap_env dev
    ;;
  prod)
    bootstrap_env prod
    ;;
esac

echo "=================================="
info "Bootstrap complete! 🎉"
echo "=================================="

echo "Run terraform init in the environment you want to use next."
