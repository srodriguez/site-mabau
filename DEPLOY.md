# Deployment Guide — mabau.com.au

Static site hosted on S3 + CloudFront, deployed via GitHub Actions on push to `main`.

---

## Overview

```
GitHub (push to main)
  → GitHub Actions (.github/workflows/deploy.yml)
    → Hugo build (--minify)
    → aws s3 sync → S3 bucket (mabau.com.au, ap-southeast-2)
    → CloudFront invalidation (E2VKLXA034ODT8)
      → serves via HTTPS at mabau.com.au + www.mabau.com.au
```

**Key IDs (already provisioned):**
| Resource | ID / Value |
|----------|-----------|
| S3 bucket | `mabau.com.au` (ap-southeast-2) |
| CloudFront distribution | `E2VKLXA034ODT8` |
| CloudFront domain | `d3uzbsmp32x4c4.cloudfront.net` |
| IAM deploy user | `mabau-deploy` |
| Contact email | `eugenia@mabau.com.au` (forwarded via ImprovMX) |

---

## 1. ACM Certificate (us-east-1)

CloudFront **requires** the certificate to be in `us-east-1` regardless of where the bucket is.

### Request

```bash
aws acm request-certificate \
  --region us-east-1 \
  --domain-name "mabau.com.au" \
  --subject-alternative-names "www.mabau.com.au" \
  --validation-method DNS \
  --query 'CertificateArn' \
  --output text
```

### Get the DNS validation records

```bash
aws acm describe-certificate \
  --region us-east-1 \
  --certificate-arn <ARN> \
  --query 'Certificate.DomainValidationOptions[].ResourceRecord' \
  --output table
```

Add both CNAME records to your DNS (Cloudflare or GoDaddy). One for `mabau.com.au`, one for `www.mabau.com.au`.

### Wait for ISSUED status

```bash
viddy -n 15 aws acm describe-certificate \
  --region us-east-1 \
  --certificate-arn <ARN> \
  --query 'Certificate.Status' \
  --output text
```

Usually 5–30 minutes once the DNS validation CNAMEs propagate.

### Attach to CloudFront

Once status is `ISSUED`, run:

```bash
./scripts/attach-cert.sh
```

The script auto-detects the issued cert and updates distribution `E2VKLXA034ODT8` in-place.
To pass the ARN explicitly: `ACM_CERT_ARN=arn:... ./scripts/attach-cert.sh`

---

## 2. S3 Bucket

Already created. To re-create from scratch:

```bash
./scripts/setup-aws.sh
```

**Manual settings (already applied):**
- Region: `ap-southeast-2` (Sydney)
- Block Public Access: all four boxes **unchecked**
- Static website hosting: **enabled**, index/error document = `index.html`
- Bucket policy: public read on `arn:aws:s3:::mabau.com.au/*`

---

## 3. CloudFront Distribution

Already created (ID: `E2VKLXA034ODT8`). Settings:

| Setting | Value |
|---------|-------|
| Origin | `mabau.com.au.s3-website-ap-southeast-2.amazonaws.com` |
| Origin protocol | HTTP only (S3 website endpoint) |
| Viewer protocol | Redirect HTTP → HTTPS |
| CNAMEs | `mabau.com.au`, `www.mabau.com.au` (added after cert is issued) |
| Cache policy | Managed-CachingOptimized |
| Price class | All edge locations |
| Default root object | `index.html` |

### Verify it's serving correctly

```bash
# Direct S3 (no CloudFront)
curl -I http://mabau.com.au.s3-website-ap-southeast-2.amazonaws.com

# Via CloudFront
curl -I https://d3uzbsmp32x4c4.cloudfront.net

# Production domain
curl -I https://mabau.com.au
curl -I https://www.mabau.com.au
```

---

## 4. DNS (GoDaddy + Cloudflare)

### Important: GoDaddy apex limitation

GoDaddy does **not** support ALIAS/ANAME records pointing to a hostname — their ALIAS record expects an IP address. CloudFront only provides a hostname, not an IP.

**Solution: use Cloudflare for DNS** (free). Cloudflare supports CNAME flattening at the apex (`@`).

### Migrate to Cloudflare

1. Create a free account at cloudflare.com
2. Add site `mabau.com.au` — Cloudflare will scan existing GoDaddy records
3. In GoDaddy → **DNS → Nameservers → Change** → enter Cloudflare's two NS records
4. Wait for nameserver propagation (up to 24h, usually under 1h)

### Cloudflare DNS records

| Type | Name | Value | Proxy |
|------|------|-------|-------|
| CNAME | `www` | `d3uzbsmp32x4c4.cloudfront.net` | DNS only |
| CNAME | `@` | `d3uzbsmp32x4c4.cloudfront.net` | DNS only |

> Use **DNS only** (grey cloud), not proxied — CloudFront handles the CDN.

### ACM certificate DNS validation CNAMEs

Also add these in Cloudflare (values from `aws acm describe-certificate`):

| Type | Name | Value |
|------|------|-------|
| CNAME | `_<hash>.mabau.com.au` | `_<hash>.acm-validations.aws` |
| CNAME | `_<hash>.www.mabau.com.au` | `_<hash>.acm-validations.aws` |

### Verify DNS propagation

```bash
dig CNAME www.mabau.com.au +short
dig CNAME mabau.com.au +short
```

Both should return `d3uzbsmp32x4c4.cloudfront.net`.

Check globally: https://dnschecker.org

---

## 5. Email Forwarding (ImprovMX)

`eugenia@mabau.com.au` forwards via ImprovMX. Add these in Cloudflare DNS:

| Type | Name | Value | Priority |
|------|------|-------|----------|
| MX | `@` | `mx1.improvmx.com` | 10 |
| MX | `@` | `mx2.improvmx.com` | 20 |
| TXT | `@` | `v=spf1 include:spf.improvmx.com ~all` | — |

> If MX records exist from a previous provider, **delete them first** before adding ImprovMX ones.

Verify:
```bash
dig MX mabau.com.au +short
dig TXT mabau.com.au +short
```

---

## 6. IAM Deploy User

User `mabau-deploy` has an inline policy scoped to this site only:
- `s3:PutObject`, `s3:DeleteObject`, `s3:ListBucket` on `mabau.com.au` bucket
- `cloudfront:CreateInvalidation` on distribution `E2VKLXA034ODT8`

To re-apply the policy:
```bash
./scripts/attach-policy.sh
```

To create a new access key (if the old one is lost):
```bash
aws iam create-access-key --user-name mabau-deploy
# Copy both AccessKeyId and SecretAccessKey — secret is shown once only
```

---

## 7. GitHub Actions Secrets

Set under **repo → Settings → Secrets and variables → Actions**:

| Secret | Value |
|--------|-------|
| `AWS_ACCESS_KEY_ID` | `mabau-deploy` IAM access key |
| `AWS_SECRET_ACCESS_KEY` | `mabau-deploy` IAM secret key |
| `S3_BUCKET` | `mabau.com.au` |
| `CLOUDFRONT_DISTRIBUTION_ID` | `E2VKLXA034ODT8` |

---

## 8. First / manual deploy

```bash
nix develop
hugo --minify
aws s3 sync public/ s3://mabau.com.au --delete
aws cloudfront create-invalidation \
  --distribution-id E2VKLXA034ODT8 \
  --paths "/*"
```

---

## 9. Scripts reference

| Script | Purpose |
|--------|---------|
| `scripts/setup-aws.sh` | Create S3 bucket + CloudFront distribution from scratch |
| `scripts/attach-cert.sh` | Attach ACM cert + CNAMEs to existing CloudFront distribution |
| `scripts/attach-policy.sh` | Attach least-privilege IAM policy to `mabau-deploy` user |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| `InvalidViewerCertificate` on CloudFront create | CNAMEs set but no cert attached | Run `attach-cert.sh` once cert is ISSUED |
| Site shows CloudFront default page | Distribution not yet propagated | Wait 10–20 min |
| `www` works but apex (`@`) doesn't | GoDaddy ALIAS limitation | Migrate DNS to Cloudflare |
| Email forwarding not working | Missing or conflicting MX records | Delete old MX records, add ImprovMX ones |
| GitHub Actions deploy fails with 403 | IAM key missing or policy too narrow | Check secrets + re-run `attach-policy.sh` |
| ACM cert stuck in `PENDING_VALIDATION` | DNS validation CNAMEs not added or not propagated | Add CNAMEs, wait for propagation |
