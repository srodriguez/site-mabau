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
      → serves via HTTPS at www.mabau.com.au
         mabau.com.au → 301 redirect → www.mabau.com.au (GoDaddy forwarding)
```

**Provisioned resources:**

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
  --query 'Certificate.DomainValidationOptions[].{Domain:DomainName,Status:ValidationStatus,Name:ResourceRecord.Name,Value:ResourceRecord.Value}' \
  --output table
```

This returns two CNAME records. Add them in GoDaddy DNS:

| Type | Name | Value |
|------|------|-------|
| CNAME | `_4c2c89c0898aa178ca82c1afff8e7646` | `_b0e80caaa00f303ea595786705c26eaa.jkddzztszm.acm-validations.aws` |
| CNAME | `_0c93bf37177dea24f40d387457021082.www` | `_bac0bca4aa1e128c6fbe1ddf5be1b1fc.jkddzztszm.acm-validations.aws` |

> **GoDaddy gotcha:** strip the trailing `.` from both Name and Value — GoDaddy appends the zone automatically. Also strip `.mabau.com.au` from the Name — GoDaddy adds that too.

### Watch for validation

```bash
viddy -n 15 aws acm describe-certificate \
  --region us-east-1 \
  --certificate-arn <ARN> \
  --query 'Certificate.{Status:Status}' \
  --output table
```

Usually **5–30 minutes** once the DNS CNAMEs propagate. Status goes `PENDING_VALIDATION` → `ISSUED`.

### Attach to CloudFront

Once status is `ISSUED`:

```bash
./scripts/attach-cert.sh
```

The script auto-detects the issued cert and updates the distribution in-place.
To pass the ARN explicitly:

```bash
ACM_CERT_ARN=arn:aws:acm:us-east-1:... ./scripts/attach-cert.sh
```

---

## 2. S3 Bucket

Already created. To re-create from scratch:

```bash
./scripts/setup-aws.sh
```

**Settings:**
- Region: `ap-southeast-2` (Sydney)
- Block Public Access: all four boxes **unchecked**
- Static website hosting: **enabled**, index/error document = `index.html`
- Bucket policy: public read on `arn:aws:s3:::mabau.com.au/*`

---

## 3. CloudFront Distribution

Already created (ID: `E2VKLXA034ODT8`).

| Setting | Value |
|---------|-------|
| Origin | `mabau.com.au.s3-website-ap-southeast-2.amazonaws.com` |
| Origin protocol | HTTP only (S3 website endpoint) |
| Viewer protocol | Redirect HTTP → HTTPS |
| CNAMEs | `mabau.com.au`, `www.mabau.com.au` |
| Cache policy | Managed-CachingOptimized |
| Price class | All edge locations |
| Default root object | `index.html` |

### Verify it's serving correctly

```bash
# Direct S3 (bypasses CloudFront — confirms S3 itself works)
curl -I http://mabau.com.au.s3-website-ap-southeast-2.amazonaws.com

# Via CloudFront domain
curl -I https://d3uzbsmp32x4c4.cloudfront.net

# Production
curl -I https://www.mabau.com.au
```

Look for `HTTP/2 200` and `x-cache: Hit from cloudfront` (on second request).

---

## 4. DNS (GoDaddy)

### Apex domain limitation

GoDaddy does **not** support ALIAS/ANAME records pointing to a hostname — their record types expect an IP address. CloudFront only provides a hostname.

**Solution used: GoDaddy URL forwarding.**
`mabau.com.au` 301-redirects to `https://www.mabau.com.au` via GoDaddy's Forwarding feature. `www` is the canonical domain served by CloudFront.

### GoDaddy DNS records

| Type | Name | Value |
|------|------|-------|
| CNAME | `www` | `d3uzbsmp32x4c4.cloudfront.net` |
| Forwarding | `@` | `https://www.mabau.com.au` (301, Forward only) |

Forwarding is configured under **GoDaddy DNS → Forwarding** (at the bottom of the DNS page), not under the regular records.

### ACM validation CNAMEs (already added)

| Type | Name | Value |
|------|------|-------|
| CNAME | `_4c2c89c0898aa178ca82c1afff8e7646` | `_b0e80caaa00f303ea595786705c26eaa.jkddzztszm.acm-validations.aws` |
| CNAME | `_0c93bf37177dea24f40d387457021082.www` | `_bac0bca4aa1e128c6fbe1ddf5be1b1fc.jkddzztszm.acm-validations.aws` |

### Verify DNS

```bash
dig CNAME www.mabau.com.au +short    # → d3uzbsmp32x4c4.cloudfront.net
dig MX mabau.com.au +short           # → mx1/mx2.improvmx.com
```

---

## 5. Email Forwarding (ImprovMX)

`eugenia@mabau.com.au` forwards via ImprovMX.

### GoDaddy DNS records (already added)

| Type | Name | Value | Priority |
|------|------|-------|----------|
| MX | `@` | `mx1.improvmx.com` | 10 |
| MX | `@` | `mx2.improvmx.com` | 20 |
| TXT | `@` | `v=spf1 include:spf.improvmx.com ~all` | — |

> If MX records from a previous provider still exist, delete them first — conflicting MX records prevent ImprovMX from validating.

Verify:
```bash
dig MX mabau.com.au +short
dig TXT mabau.com.au +short
```

---

## 6. IAM Deploy User

User `mabau-deploy` has a least-privilege inline policy:
- `s3:PutObject`, `s3:DeleteObject`, `s3:ListBucket` on `mabau.com.au` bucket only
- `cloudfront:CreateInvalidation` on distribution `E2VKLXA034ODT8` only

> **Important:** `mabau-deploy` is a separate IAM user from any other site's deploy user — intentional, to contain blast radius if the key is ever compromised.

To re-apply the policy:
```bash
./scripts/attach-policy.sh
```

To create a new access key (if lost — secret is shown once only):
```bash
aws iam create-access-key --user-name mabau-deploy
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

## 8. Manual deploy

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

| Symptom | Cause | Fix |
|---------|-------|-----|
| `403 ERROR` from CloudFront | Distribution has no CNAMEs set | Run `attach-cert.sh` once cert is ISSUED |
| `InvalidViewerCertificate` | Trying to set CNAMEs without a cert | Wait for cert to be ISSUED first, then re-run |
| Cert stuck in `PENDING_VALIDATION` | DNS validation CNAMEs not added or not propagated | Add CNAMEs in GoDaddy, strip trailing `.` from name/value |
| `www` works, apex (`@`) doesn't | GoDaddy ALIAS limitation | Use GoDaddy Forwarding: `@` → `https://www.mabau.com.au` (301) |
| Email forwarding not validating | Missing/conflicting MX records | Delete old MX records, add ImprovMX ones |
| GitHub Actions deploy fails 403 | IAM key missing or policy too narrow | Check secrets, re-run `attach-policy.sh` |
| `json.decoder.JSONDecodeError` in attach-cert.sh | Python heredoc not receiving piped input | Fixed — script now uses a temp file |
| CloudFront shows old content | Cache not invalidated | `aws cloudfront create-invalidation --distribution-id E2VKLXA034ODT8 --paths "/*"` |
