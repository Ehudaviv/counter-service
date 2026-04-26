#!/usr/bin/env bash

# ==============================================================================
# AWS FOUNDATION BOOTSTRAP
# ------------------------------------------------------------------------------# 
# Purpose:
# 1. Provisions S3/DynamoDB for Terraform remote state & locking.
# 2. Configures GitHub OIDC integration.
# 3. Sets up IAM roles for Terraform (Admin) and Docker builds (ECR).
# ==============================================================================

set -euo pipefail

# --- Configuration Variables ---
TARGET_REGION="eu-west-2"
APP_PREFIX="ehud-counter-service"
VCS_ORG="Ehudaviv"
VCS_REPO="counter-service"

# --- Resource Names ---
TF_S3_BUCKET="${APP_PREFIX}-tfstate"
TF_LOCK_TABLE="${APP_PREFIX}-tfstate-lock"
IAM_ROLE_TF="${APP_PREFIX}-terraform-ci"
IAM_ROLE_APP="${APP_PREFIX}-github-actions-role"

echo "[*] Starting AWS infrastructure bootstrap for ${APP_PREFIX}..."

# ------------------------------------------------------------------------------
# Phase 1: Terraform Remote State Storage
# ------------------------------------------------------------------------------
echo ">>> Setting up Terraform State Backend (S3 + DynamoDB)"

if ! aws s3api head-bucket --bucket "$TF_S3_BUCKET" >/dev/null 2>&1; then
    echo "    -> Provisioning S3 bucket: $TF_S3_BUCKET"
    aws s3api create-bucket \
        --bucket "$TF_S3_BUCKET" \
        --region "$TARGET_REGION" \
        --create-bucket-configuration LocationConstraint="$TARGET_REGION" >/dev/null
    
    # Enforce versioning
    aws s3api put-bucket-versioning \
        --bucket "$TF_S3_BUCKET" \
        --versioning-configuration Status=Enabled
        
    # Enforce AES256 encryption at rest
    aws s3api put-bucket-encryption \
        --bucket "$TF_S3_BUCKET" \
        --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
else
    echo "    -> S3 bucket '$TF_S3_BUCKET' is already active."
fi

if ! aws dynamodb describe-table --table-name "$TF_LOCK_TABLE" --region "$TARGET_REGION" >/dev/null 2>&1; then
    echo "    -> Provisioning DynamoDB lock table: $TF_LOCK_TABLE"
    aws dynamodb create-table \
        --table-name "$TF_LOCK_TABLE" \
        --attribute-definitions AttributeName=LockID,AttributeType=S \
        --key-schema AttributeName=LockID,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --region "$TARGET_REGION" >/dev/null
else
    echo "    -> DynamoDB table '$TF_LOCK_TABLE' is already active."
fi

# ------------------------------------------------------------------------------
# Phase 2: OpenID Connect (OIDC) Setup
# ------------------------------------------------------------------------------
echo ">>> Verifying GitHub OIDC Provider"

GITHUB_OIDC_ARN=$(aws iam list-open-id-connect-providers \
    --query "OpenIDConnectProviderList[?ends_with(Arn,'token.actions.githubusercontent.com')].Arn" \
    --output text)

if [[ -z "$GITHUB_OIDC_ARN" || "$GITHUB_OIDC_ARN" == "None" ]]; then
    echo "    -> Registering GitHub OIDC provider in AWS..."
    GITHUB_OIDC_ARN=$(aws iam create-open-id-connect-provider \
        --url https://token.actions.githubusercontent.com \
        --client-id-list sts.amazonaws.com \
        --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1 1c58a3a8518e8759bf075b76b750d4f2df264fcd \
        --query OpenIDConnectProviderArn \
        --output text)
else
    echo "    -> GitHub OIDC provider verified."
fi

AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)

# Prepare Trust Policy Document
POLICY_TMP=$(mktemp)
cat <<JSON_EOF > "$POLICY_TMP"
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Federated": "$GITHUB_OIDC_ARN" },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": { "token.actions.githubusercontent.com:aud": "sts.amazonaws.com" },
        "StringLike": { "token.actions.githubusercontent.com:sub": "repo:$VCS_ORG/$VCS_REPO:*" }
      }
    }
  ]
}
JSON_EOF

# ------------------------------------------------------------------------------
# Phase 3: Provision IAM Roles
# ------------------------------------------------------------------------------
echo ">>> Configuring IAM Roles for CI/CD pipelines"

# 3A: Terraform Execution Role
if ! aws iam get-role --role-name "$IAM_ROLE_TF" >/dev/null 2>&1; then
    echo "    -> Creating Pipeline Role: $IAM_ROLE_TF (Admin)"
    aws iam create-role --role-name "$IAM_ROLE_TF" --assume-role-policy-document file://"$POLICY_TMP" >/dev/null
    aws iam attach-role-policy --role-name "$IAM_ROLE_TF" --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
else
    echo "    -> Updating trust policy for existing role: $IAM_ROLE_TF"
    aws iam update-assume-role-policy --role-name "$IAM_ROLE_TF" --policy-document file://"$POLICY_TMP"
fi

# 3B: ECR Push Role
if ! aws iam get-role --role-name "$IAM_ROLE_APP" >/dev/null 2>&1; then
    echo "    -> Creating App Build Role: $IAM_ROLE_APP (ECR Push)"
    aws iam create-role --role-name "$IAM_ROLE_APP" --assume-role-policy-document file://"$POLICY_TMP" >/dev/null

    ECR_PERMS=$(mktemp)
    cat <<JSON_EOF > "$ECR_PERMS"
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchGetImage",
        "ecr:BatchCheckLayerAvailability",
        "ecr:CompleteLayerUpload",
        "ecr:GetDownloadUrlForLayer",
        "ecr:InitiateLayerUpload",
        "ecr:PutImage",
        "ecr:UploadLayerPart",
        "eks:DescribeCluster"
      ],
      "Resource": "*"
    }
  ]
}
JSON_EOF

    aws iam put-role-policy --role-name "$IAM_ROLE_APP" --policy-name ecr-publish-access --policy-document file://"$ECR_PERMS"
    rm -f "$ECR_PERMS"
else
    echo "    -> App Build Role '$IAM_ROLE_APP' already configured."
fi

rm -f "$POLICY_TMP"

echo ""
echo "[✔] Foundation successfully provisioned."
echo "------------------------------------------------------------------------------"
echo "Terraform Role ARN : arn:aws:iam::${AWS_ACCOUNT}:role/${IAM_ROLE_TF}"
echo "Actions Role ARN   : arn:aws:iam::${AWS_ACCOUNT}:role/${IAM_ROLE_APP}"
echo "------------------------------------------------------------------------------"