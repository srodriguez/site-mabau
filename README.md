# Mabau — mabau.com.au

Static site for Mabau, an Australian family owned company selling fine Argentine leather bags.

**Stack:** Hugo · Nix · GitHub Actions · AWS S3 + CloudFront

---

## Prerequisites

[Nix](https://nixos.org/download/) with flakes enabled. That's it — Hugo is provided by the dev shell.

To enable flakes, add this to `~/.config/nix/nix.conf` (or `/etc/nix/nix.conf`):

```
experimental-features = nix-command flakes
```

---

## Local development

```bash
nix develop          # enter the dev shell (installs Hugo)
hugo server          # serve at http://localhost:1313 with live reload
```

To preview with drafts:

```bash
hugo server --buildDrafts
```

---

## Build

```bash
nix develop --command hugo --minify
```

Output goes to `public/`. This directory is git-ignored.

Or build as a Nix derivation (output symlinked to `./result`):

```bash
nix build
```

---

## Configuration

All site settings live in `hugo.toml`:

```toml
[params]
  tagline = 'Coming Soon'
  email   = ''          # set this to show a mailto link on the page
```

To add a contact email, set `email = 'hello@mabau.com.au'` and push to `main`.

---

## Deployment

Pushing to `main` triggers the GitHub Actions workflow (`.github/workflows/deploy.yml`), which:

1. Builds the site with Hugo
2. Syncs `public/` to the S3 bucket (HTML with `no-cache`, assets with long-lived `immutable` headers)
3. Invalidates the CloudFront distribution cache

### Required GitHub secrets

| Secret | Value |
|--------|-------|
| `AWS_ACCESS_KEY_ID` | IAM user access key |
| `AWS_SECRET_ACCESS_KEY` | IAM user secret key |
| `S3_BUCKET` | `mabau.com.au` |
| `CLOUDFRONT_DISTRIBUTION_ID` | e.g. `E2ABCDEF123456` |

Set these under **Settings → Secrets and variables → Actions** in the GitHub repo.

---

## First-time AWS + DNS setup

Full step-by-step instructions are in [`DEPLOY.md`](./DEPLOY.md), covering:

- ACM certificate (us-east-1) for `mabau.com.au` and `www.mabau.com.au`
- S3 bucket creation and static website hosting config
- CloudFront distribution with origin access control
- GoDaddy DNS — CNAME for `www`, ALIAS/ANAME for the apex (`@`)
- IAM user with least-privilege policy for the deploy workflow

---

## Project structure

```
.
├── hugo.toml                       # site config
├── content/_index.md               # home page front matter
├── layouts/index.html              # single-page layout (no theme)
├── static/                         # static assets (images, fonts, etc.)
├── flake.nix                       # Nix dev shell + build derivation
├── .github/workflows/deploy.yml    # CI/CD pipeline
└── DEPLOY.md                       # AWS + DNS setup guide
```
