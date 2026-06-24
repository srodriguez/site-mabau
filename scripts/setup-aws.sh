#!/usr/bin/env bash
# setup-aws.sh — provision S3 + CloudFront for mabau.com.au
#
# Usage:
#   ./scripts/setup-aws.sh
#
# What it does:
#   1. Checks AWS credentials
#   2. Creates the S3 bucket with static website hosting
#   3. Looks up an issued ACM certificate for mabau.com.au in us-east-1
#   4. Creates a CloudFront distribution
#      - With CNAMEs if a cert was found
#      - Without CNAMEs if no cert yet (safe fallback — add them later)
#   5. Prints the CloudFront domain + GitHub secrets to copy

set -euo pipefail

BUCKET="mabau.com.au"
REGION="ap-southeast-2"

# ─── colours ────────────────────────────────────────────────
GREEN='\033[0;32m'; ORANGE='\033[0;33m'; RED='\033[0;31m'; RESET='\033[0m'
info()  { echo -e "${GREEN}▶ $*${RESET}"; }
warn()  { echo -e "${ORANGE}⚠ $*${RESET}"; }
error() { echo -e "${RED}✖ $*${RESET}"; }

# ─── 1. AWS auth check ───────────────────────────────────────
echo ""
info "Checking AWS credentials..."

if ! aws sts get-caller-identity --output text --query 'Account' &>/dev/null; then
  error "Not authenticated with AWS."
  echo ""
  echo "  Run one of the following, then re-run this script:"
  echo ""
  echo "  Option A — long-term IAM credentials (simplest):"
  echo "    aws configure"
  echo "    # prompts for: Access Key ID, Secret Access Key, region (ap-southeast-2), output (json)"
  echo ""
  echo "  Option B — SSO / IAM Identity Center:"
  echo "    aws configure sso"
  echo "    aws sso login --profile <profile-name>"
  echo ""
  echo "  Option C — environment variables:"
  echo "    export AWS_ACCESS_KEY_ID=..."
  echo "    export AWS_SECRET_ACCESS_KEY=..."
  echo "    export AWS_DEFAULT_REGION=ap-southeast-2"
  echo ""
  exit 1
fi

ACCOUNT=$(aws sts get-caller-identity --query 'Account' --output text)
IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
info "Authenticated as: ${IDENTITY} (account: ${ACCOUNT})"
echo ""

# ─── 2. S3 bucket ────────────────────────────────────────────
info "Creating S3 bucket: $BUCKET in $REGION"

if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  warn "Bucket $BUCKET already exists — skipping creation"
else
  aws s3api create-bucket \
    --bucket "$BUCKET" \
    --region "$REGION" \
    --create-bucket-configuration LocationConstraint="$REGION"
  info "Bucket created"
fi

info "Disabling Block Public Access..."
aws s3api put-public-access-block \
  --bucket "$BUCKET" \
  --public-access-block-configuration \
    "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false"

info "Enabling static website hosting..."
aws s3api put-bucket-website \
  --bucket "$BUCKET" \
  --website-configuration '{
    "IndexDocument": {"Suffix": "index.html"},
    "ErrorDocument": {"Key": "index.html"}
  }'

info "Applying bucket policy (public read)..."
aws s3api put-bucket-policy \
  --bucket "$BUCKET" \
  --policy "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [{
      \"Sid\": \"PublicReadGetObject\",
      \"Effect\": \"Allow\",
      \"Principal\": \"*\",
      \"Action\": \"s3:GetObject\",
      \"Resource\": \"arn:aws:s3:::${BUCKET}/*\"
    }]
  }"

info "S3 website endpoint: http://${BUCKET}.s3-website-${REGION}.amazonaws.com"
echo ""

# ─── 3. ACM certificate lookup ───────────────────────────────
# CloudFront requires the cert to be in us-east-1, regardless of bucket region.
# We accept an explicit ARN via env var, or auto-detect an issued cert.

ACM_CERT_ARN="${ACM_CERT_ARN:-}"

if [[ -z "$ACM_CERT_ARN" ]]; then
  info "Looking for an issued ACM certificate for ${BUCKET} in us-east-1..."
  ACM_CERT_ARN=$(aws acm list-certificates \
    --region us-east-1 \
    --certificate-statuses ISSUED \
    --query "CertificateSummaryList[?contains(DomainName, 'mabau.com.au')].CertificateArn | [0]" \
    --output text 2>/dev/null || true)

  # list-certificates returns "None" (string) when there are no matches
  if [[ "$ACM_CERT_ARN" == "None" || -z "$ACM_CERT_ARN" ]]; then
    ACM_CERT_ARN=""
  fi
fi

# ─── 4. CloudFront distribution ──────────────────────────────
info "Creating CloudFront distribution..."

ORIGIN_DOMAIN="${BUCKET}.s3-website-${REGION}.amazonaws.com"
CALLER_REF="mabau-$(date +%s)"

if [[ -n "$ACM_CERT_ARN" ]]; then
  info "Using ACM certificate: ${ACM_CERT_ARN}"
  ALIASES_BLOCK='"Aliases": {"Quantity": 2, "Items": ["mabau.com.au", "www.mabau.com.au"]},'
  VIEWER_CERT_BLOCK="\"ViewerCertificate\": {
    \"ACMCertificateArn\": \"${ACM_CERT_ARN}\",
    \"SSLSupportMethod\": \"sni-only\",
    \"MinimumProtocolVersion\": \"TLSv1.2_2021\"
  }"
  CERT_NOTE="with CNAMEs mabau.com.au + www.mabau.com.au"
else
  warn "No issued ACM certificate found for mabau.com.au in us-east-1."
  warn "Creating distribution WITHOUT custom domain names (safe fallback)."
  warn "Once your certificate is issued, re-run this script or add the CNAMEs"
  warn "manually: CloudFront Console → distribution → Edit → Alternate domain names."
  echo ""
  ALIASES_BLOCK='"Aliases": {"Quantity": 0},'
  VIEWER_CERT_BLOCK='"ViewerCertificate": {"CloudFrontDefaultCertificate": true, "MinimumProtocolVersion": "TLSv1"}'
  CERT_NOTE="WITHOUT custom domain (no cert found — add CNAMEs after cert is issued)"
fi

DISTRIBUTION=$(aws cloudfront create-distribution \
  --region us-east-1 \
  --distribution-config "{
    \"CallerReference\": \"${CALLER_REF}\",
    \"Comment\": \"mabau.com.au\",
    \"Enabled\": true,
    \"HttpVersion\": \"http2and3\",
    \"PriceClass\": \"PriceClass_All\",
    \"DefaultRootObject\": \"index.html\",
    ${ALIASES_BLOCK}
    \"Origins\": {
      \"Quantity\": 1,
      \"Items\": [{
        \"Id\": \"s3-website\",
        \"DomainName\": \"${ORIGIN_DOMAIN}\",
        \"CustomOriginConfig\": {
          \"HTTPPort\": 80,
          \"HTTPSPort\": 443,
          \"OriginProtocolPolicy\": \"http-only\"
        }
      }]
    },
    \"DefaultCacheBehavior\": {
      \"TargetOriginId\": \"s3-website\",
      \"ViewerProtocolPolicy\": \"redirect-to-https\",
      \"CachePolicyId\": \"658327ea-f89d-4fab-a63d-7e88639e58f6\",
      \"Compress\": true,
      \"AllowedMethods\": {
        \"Quantity\": 2,
        \"Items\": [\"GET\", \"HEAD\"]
      }
    },
    ${VIEWER_CERT_BLOCK}
  }")

CF_DOMAIN=$(echo "$DISTRIBUTION" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['Distribution']['DomainName'])")
CF_ID=$(echo "$DISTRIBUTION"     | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['Distribution']['Id'])")

# ─── 5. Summary ──────────────────────────────────────────────
echo ""
echo "────────────────────────────────────────────────────────"
info "CloudFront distribution created (${CERT_NOTE})"
echo ""
info "Add these secrets to GitHub → Settings → Secrets → Actions:"
echo ""
echo "  AWS_ACCESS_KEY_ID           <your IAM deploy key>"
echo "  AWS_SECRET_ACCESS_KEY       <your IAM deploy secret>"
echo "  S3_BUCKET                   ${BUCKET}"
echo "  CLOUDFRONT_DISTRIBUTION_ID  ${CF_ID}"
echo ""
info "GoDaddy DNS — add these records:"
echo ""
echo "  CNAME  www  →  ${CF_DOMAIN}"
echo "  ALIAS  @    →  ${CF_DOMAIN}   (GoDaddy calls this ALIAS or ANAME)"
echo ""
info "CloudFront domain: ${CF_DOMAIN}"
info "Distribution ID:   ${CF_ID}"
echo ""
if [[ -z "$ACM_CERT_ARN" ]]; then
  warn "Next step: once your ACM certificate is issued in us-east-1, re-run:"
  warn "  ACM_CERT_ARN=<arn> ./scripts/setup-aws.sh"
  warn "  (the script will skip the bucket and update only the distribution)"
  echo ""
fi
warn "CloudFront propagation takes 10–20 min on first deploy."
echo "────────────────────────────────────────────────────────"
