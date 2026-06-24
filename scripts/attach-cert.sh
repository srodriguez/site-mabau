#!/usr/bin/env bash
# attach-cert.sh — attach an ACM certificate + CNAMEs to the existing CloudFront distribution
#
# Usage:
#   ACM_CERT_ARN=arn:aws:acm:us-east-1:... ./scripts/attach-cert.sh

set -euo pipefail

CF_ID="E2VKLXA034ODT8"

GREEN='\033[0;32m'; ORANGE='\033[0;33m'; RED='\033[0;31m'; RESET='\033[0m'
info()  { echo -e "${GREEN}▶ $*${RESET}"; }
warn()  { echo -e "${ORANGE}⚠ $*${RESET}"; }
error() { echo -e "${RED}✖ $*${RESET}"; }

# ─── cert ARN ────────────────────────────────────────────────
ACM_CERT_ARN="${ACM_CERT_ARN:-}"

if [[ -z "$ACM_CERT_ARN" ]]; then
  info "ACM_CERT_ARN not set — looking for issued cert in us-east-1..."
  ACM_CERT_ARN=$(aws acm list-certificates \
    --region us-east-1 \
    --certificate-statuses ISSUED \
    --query "CertificateSummaryList[?contains(DomainName, 'mabau.com.au')].CertificateArn | [0]" \
    --output text 2>/dev/null || true)

  if [[ "$ACM_CERT_ARN" == "None" || -z "$ACM_CERT_ARN" ]]; then
    error "No issued ACM certificate found for mabau.com.au in us-east-1."
    echo ""
    echo "  Request one in the AWS Console → Certificate Manager (region: us-east-1)"
    echo "  Add DNS validation CNAME records in GoDaddy/Cloudflare, then wait for Issued status."
    echo "  Then re-run this script."
    exit 1
  fi
fi

info "Using certificate: ${ACM_CERT_ARN}"

# ─── fetch current distribution config ───────────────────────
info "Fetching current distribution config..."
TMPFILE=$(mktemp /tmp/cf-config.XXXXXX.json)
trap "rm -f $TMPFILE" EXIT

aws cloudfront get-distribution-config --id "$CF_ID" --region us-east-1 > "$TMPFILE"
ETAG=$(python3 -c "import json; print(json.load(open('$TMPFILE'))['ETag'])")

# ─── patch: add CNAMEs + certificate ─────────────────────────
info "Patching config with CNAMEs and certificate..."
UPDATED=$(python3 << PYEOF
import json

with open('$TMPFILE') as f:
    data = json.load(f)

cfg = data['DistributionConfig']

cfg['Aliases'] = {
    'Quantity': 2,
    'Items': ['mabau.com.au', 'www.mabau.com.au']
}

cfg['ViewerCertificate'] = {
    'ACMCertificateArn':      '$ACM_CERT_ARN',
    'SSLSupportMethod':       'sni-only',
    'MinimumProtocolVersion': 'TLSv1.2_2021',
    'Certificate':            '$ACM_CERT_ARN',
    'CertificateSource':      'acm'
}

print(json.dumps(cfg))
PYEOF
)

# ─── apply update ─────────────────────────────────────────────
info "Updating distribution ${CF_ID}..."
aws cloudfront update-distribution \
  --id "$CF_ID" \
  --region us-east-1 \
  --if-match "$ETAG" \
  --distribution-config "$UPDATED" \
  --output table --query 'Distribution.{ID:Id,Status:Status,Domain:DomainName}'

echo ""
info "Done. Distribution is deploying — takes ~5 min to propagate."
warn "DNS records to add (if not already set):"
echo ""
echo "  CNAME  www  →  d3uzbsmp32x4c4.cloudfront.net"
echo "  CNAME  @    →  d3uzbsmp32x4c4.cloudfront.net  (via Cloudflare flattening)"
