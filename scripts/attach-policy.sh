#!/usr/bin/env bash
# attach-policy.sh — attach least-privilege deploy policy to mabau-deploy IAM user

set -euo pipefail

GREEN='\033[0;32m'; RESET='\033[0m'
info() { echo -e "${GREEN}▶ $*${RESET}"; }

IAM_USER="mabau-deploy"
CF_ID="E2VKLXA034ODT8"
BUCKET="mabau.com.au"

ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
info "Account ID: ${ACCOUNT_ID}"

info "Attaching policy to ${IAM_USER}..."

aws iam put-user-policy \
  --user-name "$IAM_USER" \
  --policy-name mabau-deploy-policy \
  --policy-document "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [
      {
        \"Effect\": \"Allow\",
        \"Action\": [\"s3:PutObject\", \"s3:DeleteObject\", \"s3:ListBucket\"],
        \"Resource\": [
          \"arn:aws:s3:::${BUCKET}\",
          \"arn:aws:s3:::${BUCKET}/*\"
        ]
      },
      {
        \"Effect\": \"Allow\",
        \"Action\": \"cloudfront:CreateInvalidation\",
        \"Resource\": \"arn:aws:cloudfront::${ACCOUNT_ID}:distribution/${CF_ID}\"
      }
    ]
  }"

info "Done. Policy attached to ${IAM_USER}:"
echo ""
echo "  S3 bucket:              ${BUCKET}"
echo "  CloudFront distribution: ${CF_ID}"
echo ""
info "Verify with:"
echo "  aws iam get-user-policy --user-name ${IAM_USER} --policy-name mabau-deploy-policy"
