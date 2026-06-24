#!/usr/bin/env bash
# setup-aws.sh — provision S3 + CloudFront for mabau.com.au
#
# Prerequisites:
#   - AWS CLI installed and authenticated (run: aws configure)
#   - ACM certificate already issued in us-east-1 (see DEPLOY.md step 1)
#
# Usage:
#   chmod +x scripts/setup-aws.sh
#   ./scripts/setup-aws.sh
#
# What it does:
#   1. Creates the S3 bucket with static website hosting
#   2. Applies a bucket policy allowing public read
#   3. Creates a CloudFront distribution pointing at the bucket
#   4. Prints the CloudFront domain + the secrets you need to add to GitHub

set -euo pipefail

BUCKET="mabau.com.au"
REGION="ap-southeast-2"

# ─── colours ────────────────────────────────────────────────
GREEN='\033[0;32m'; ORANGE='\033[0;33m'; RESET='\033[0m'
info()    { echo -e "${GREEN}▶ $*${RESET}"; }
warn()    { echo -e "${ORANGE}⚠ $*${RESET}"; }

# ─── 1. S3 bucket ────────────────────────────────────────────
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

# ─── 2. CloudFront distribution ──────────────────────────────
info "Creating CloudFront distribution..."

# You must have an ACM cert in us-east-1 for mabau.com.au + www.mabau.com.au.
# Find its ARN with:
#   aws acm list-certificates --region us-east-1
#
# Then set it here:
ACM_CERT_ARN="${ACM_CERT_ARN:-}"

if [[ -z "$ACM_CERT_ARN" ]]; then
  warn "ACM_CERT_ARN not set — CloudFront will be created WITHOUT a custom SSL cert."
  warn "Re-run with: ACM_CERT_ARN=arn:aws:acm:us-east-1:... ./scripts/setup-aws.sh"
  warn "Or update the distribution in the AWS Console after the cert is ready."
  VIEWER_CERT='"ViewerCertificate": {"CloudFrontDefaultCertificate": true}'
else
  VIEWER_CERT="\"ViewerCertificate\": {
    \"ACMCertificateArn\": \"${ACM_CERT_ARN}\",
    \"SSLSupportMethod\": \"sni-only\",
    \"MinimumProtocolVersion\": \"TLSv1.2_2021\"
  }"
fi

ORIGIN_DOMAIN="${BUCKET}.s3-website-${REGION}.amazonaws.com"
CALLER_REF="mabau-$(date +%s)"

DISTRIBUTION=$(aws cloudfront create-distribution \
  --region us-east-1 \
  --distribution-config "{
    \"CallerReference\": \"${CALLER_REF}\",
    \"Comment\": \"mabau.com.au\",
    \"Enabled\": true,
    \"HttpVersion\": \"http2and3\",
    \"PriceClass\": \"PriceClass_All\",
    \"DefaultRootObject\": \"index.html\",
    \"Aliases\": {
      \"Quantity\": 2,
      \"Items\": [\"mabau.com.au\", \"www.mabau.com.au\"]
    },
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
    ${VIEWER_CERT}
  }")

CF_DOMAIN=$(echo "$DISTRIBUTION" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['Distribution']['DomainName'])")
CF_ID=$(echo "$DISTRIBUTION"     | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['Distribution']['Id'])")

echo ""
echo "────────────────────────────────────────────────────────"
info "Done! Add these secrets to GitHub → Settings → Secrets:"
echo ""
echo "  AWS_ACCESS_KEY_ID        <your IAM key>"
echo "  AWS_SECRET_ACCESS_KEY    <your IAM secret>"
echo "  S3_BUCKET                ${BUCKET}"
echo "  CLOUDFRONT_DISTRIBUTION_ID  ${CF_ID}"
echo ""
info "GoDaddy DNS — add these records:"
echo ""
echo "  CNAME  www  →  ${CF_DOMAIN}"
echo "  ALIAS  @    →  ${CF_DOMAIN}"
echo ""
info "CloudFront domain: ${CF_DOMAIN}"
info "Distribution ID:   ${CF_ID}"
echo ""
warn "CloudFront propagation takes 10–20 min on first deploy."
echo "────────────────────────────────────────────────────────"
