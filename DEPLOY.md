# Deployment Guide — mabau.com.au

Static site hosted on S3 + CloudFront, deployed via GitHub Actions on push to `main`.

---

## 1. ACM Certificate (must be in us-east-1)

1. Open **AWS Certificate Manager** — switch region to **US East (N. Virginia)**.
2. Click **Request** → **Request a public certificate**.
3. Add domain names: `mabau.com.au` and `www.mabau.com.au`.
4. Choose **DNS validation** → **Request**.
5. Expand the certificate and copy the CNAME name/value for each domain.
6. In GoDaddy DNS, add both CNAME records (strip the trailing `.` from the value if GoDaddy adds it automatically).
7. Wait for status to show **Issued** (usually 5–30 min).

---

## 2. S3 Bucket

1. Open **S3** → **Create bucket**.
2. **Bucket name**: `mabau.com.au` (must match the domain exactly).
3. **Region**: `ap-southeast-2` (Sydney).
4. **Block Public Access**: uncheck all four boxes → confirm.
5. Create the bucket.
6. Go to the bucket → **Properties** → **Static website hosting** → **Enable**.
   - Index document: `index.html`
   - Error document: `index.html`
7. Note the **Bucket website endpoint** (you won't use it directly — CloudFront will be the origin).

### Bucket policy (allow CloudFront OAC)

After creating the CloudFront distribution (step 3), S3 will prompt you to copy a
generated bucket policy. Paste it under **Permissions → Bucket policy**.

---

## 3. CloudFront Distribution

1. Open **CloudFront** → **Create distribution**.
2. **Origin domain**: select the S3 bucket (`mabau.com.au.s3.ap-southeast-2.amazonaws.com`).
   - Do **not** use the S3 website endpoint here.
3. **Origin access**: **Origin access control (OAC)** → **Create new OAC** (default settings).
4. **Viewer protocol policy**: **Redirect HTTP to HTTPS**.
5. **Alternate domain names (CNAMEs)**: add `mabau.com.au` and `www.mabau.com.au`.
6. **Custom SSL certificate**: select the ACM certificate created in step 1.
7. **Default root object**: `index.html`.
8. **Price class**: `Use only North America and Europe` — or `All edge locations` for AU-focused latency (recommended).
9. Create distribution.
10. Copy the S3 bucket policy that CloudFront generates and apply it to the bucket (step 2).
11. Note the **Distribution domain name** (e.g. `d1abc123xyz.cloudfront.net`) — needed for DNS.

---

## 4. GoDaddy DNS

| Type  | Name | Value                              | Notes                                      |
|-------|------|------------------------------------|--------------------------------------------|
| CNAME | www  | `d1abc123xyz.cloudfront.net`       | Replace with your actual CF domain         |
| ALIAS | @    | `d1abc123xyz.cloudfront.net`       | GoDaddy calls this "ALIAS" or "ANAME"      |

> **Apex records**: GoDaddy supports an ALIAS/ANAME record type for the root domain (`@`),
> which resolves to an IP at query time. Use this instead of A records so the apex points
> at CloudFront. If GoDaddy's UI only shows A/CNAME, look for "ALIAS" in the record type
> dropdown.

TTL: 600 seconds (10 min) initially; increase to 3600 once stable.

---

## 5. GitHub Actions Secrets

In your GitHub repo → **Settings → Secrets and variables → Actions**, add:

| Secret name                  | Value                                      |
|------------------------------|--------------------------------------------|
| `AWS_ACCESS_KEY_ID`          | IAM user access key (see below)            |
| `AWS_SECRET_ACCESS_KEY`      | IAM user secret key                        |
| `S3_BUCKET`                  | `mabau.com.au`                             |
| `CLOUDFRONT_DISTRIBUTION_ID` | From the CloudFront console (e.g. `E2...`) |

### IAM user permissions

Create a dedicated IAM user with this inline policy (least privilege):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:PutObject", "s3:DeleteObject", "s3:ListBucket"],
      "Resource": [
        "arn:aws:s3:::mabau.com.au",
        "arn:aws:s3:::mabau.com.au/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": "cloudfront:CreateInvalidation",
      "Resource": "arn:aws:cloudfront::<ACCOUNT_ID>:distribution/<DISTRIBUTION_ID>"
    }
  ]
}
```

Replace `<ACCOUNT_ID>` and `<DISTRIBUTION_ID>` with your actual values.

---

## 6. First Deploy

Push to `main` — the workflow will build with Hugo and sync to S3 automatically.

Check the **Actions** tab in GitHub to monitor progress. First propagation through
CloudFront can take 5–15 minutes.

---

## Adding the Contact Email

Once you have the email address, edit `hugo.toml`:

```toml
[params]
  email = 'hello@mabau.com.au'
```

Commit and push — the mailto link will appear on the site automatically.
