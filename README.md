# Mabau — mabau.com.au

Static site for Mabau, an Australian family owned company selling fine Argentine leather bags.

**Stack:** Hugo · Nix · GitHub Actions · AWS S3 + CloudFront

---

## Prerequisites

[Nix](https://nixos.org/download/) with flakes enabled. Everything else (Hugo, etc.) is provided by the dev shell.

Enable flakes in `~/.config/nix/nix.conf`:

```
experimental-features = nix-command flakes
```

---

## Local development

```bash
nix develop                  # enter the dev shell (provides Hugo + git)
hugo server                  # live-reload dev server at http://localhost:1313
hugo server --buildDrafts    # include draft content
```

---

## Build

```bash
# Build via Hugo directly (inside nix develop shell):
hugo --minify

# Or as a Nix derivation (output symlinked to ./result):
nix build
```

Output goes to `public/`. This directory is git-ignored.

---

## Configuration

All site settings are in `hugo.toml`:

```toml
[params]
  tagline = 'Coming Soon'
  email   = 'eugenia@mabau.com.au'   # drives the contact link + CTA
```

Change and push to `main` — the site deploys automatically.

---

## Adding / replacing images

| Path | Purpose |
|------|---------|
| `static/images/logos/` | Brand logo (SVG + PNG). `mabau-logo.svg` is used in the header. |
| `static/images/models/` | Gallery & hero images. |

**Naming convention:** use lowercase kebab-case (`my-bag.jpeg`). Spaces in filenames break web URLs.

To change the **hero image**, edit the `src` of the first `<img>` inside `<section class="hero">` in `layouts/index.html`.

To add a **gallery image**, add a `<div class="gallery-item"><img src="..." /></div>` block inside `<section class="gallery">` in `layouts/index.html`.

---

## Site structure

```
layouts/index.html        single-page layout — edit this for content/design changes
static/images/
  logos/mabau-logo.svg    header logo
  models/                 gallery images (20 model shots)
hugo.toml                 site config (email, tagline, baseURL)
content/_index.md         home page front matter stub
```

### Page sections (top → bottom)

1. **Header** — sticky, logo left, contact email right
2. **Hero** — split screen: brand copy left, `dione-oro.png` right
3. **Intro strip** — three pillars: Origin / Material / Family owned
4. **Gallery** — CSS masonry, 12 curated images, hover zoom
5. **Contact CTA** — dark section with mailto link
6. **Footer** — copyright

---

## Deployment

Push to `main` → GitHub Actions builds with Hugo → syncs to S3 → invalidates CloudFront.

The workflow is at `.github/workflows/deploy.yml`. It uses these repository secrets:

| Secret | Value |
|--------|-------|
| `AWS_ACCESS_KEY_ID` | IAM user access key |
| `AWS_SECRET_ACCESS_KEY` | IAM user secret key |
| `S3_BUCKET` | `mabau.com.au` |
| `CLOUDFRONT_DISTRIBUTION_ID` | e.g. `E2ABCDEF123456` |

Set these under **Settings → Secrets and variables → Actions** in GitHub.

---

## First-time AWS setup (automated script)

```bash
# 1. Install and authenticate AWS CLI
aws configure   # enter your Access Key ID, Secret, region: ap-southeast-2

# 2. (Optional) set your ACM cert ARN — get it from AWS Console → Certificate Manager (us-east-1)
export ACM_CERT_ARN=arn:aws:acm:us-east-1:123456789:certificate/abc-...

# 3. Run the setup script
./scripts/setup-aws.sh
```

The script will:
- Create the S3 bucket with public static website hosting
- Create the CloudFront distribution
- Print the CloudFront domain + the exact GitHub secrets values to copy

For manual step-by-step AWS Console instructions, see [`DEPLOY.md`](./DEPLOY.md).

---

## Future development

### Adding new pages

This is currently a **single-page site** (one `layouts/index.html`, no menu, no blog).
To add new pages when ready (e.g. a collections page or about page):

1. Create `content/collections/_index.md`
2. Create `layouts/collections/list.html`
3. Add a `<nav>` to the header in `index.html`
4. Remove `disableKinds` entries from `hugo.toml` as needed

### Adding a product catalogue

The simplest approach: add a `data/products.json` file and iterate over it in the template with Hugo's `range` function — no CMS needed.

```json
[
  { "name": "Dione Oro", "image": "dione-oro.png", "description": "Gold studded hobo" }
]
```

In the template:
```html
{{ range .Site.Data.products }}
  <div class="product">
    <img src="/images/models/{{ .image }}" alt="{{ .name }}" />
    <h3>{{ .name }}</h3>
  </div>
{{ end }}
```

### Swapping images

All gallery images are in `static/images/models/`. Drop new files there, add them to the `<section class="gallery">` in `layouts/index.html`, and push.

### Changing the colour palette

All colours are CSS custom properties at the top of `layouts/index.html`:

```css
:root {
  --cream:  #f5f0e8;
  --dark:   #111009;
  --orange: #e86e3a;   /* matches the brand logo */
  --muted:  #7a6e60;
  --border: #ddd5c8;
}
```

### Performance / SEO

- Images are loaded with `loading="lazy"` — no action needed for above-the-fold perf.
- To add OG/Twitter meta tags, add them inside `<head>` in `layouts/index.html`.
- To add Google Analytics, paste the GA snippet before `</head>`.

---

## Installed image files

| Filename | Description |
|----------|-------------|
| `dione-oro.png` | **Hero** — gold studded hobo, model in black blazer |
| `olivia-dorada.jpeg` | Gold metallic backpack, white bg |
| `sophia-chain-bags.jpeg` | Multiple metallic chain shoulder bags |
| `devi-print.png` | Leopard crossbody, studio |
| `inti-negra-charol.png` | Black patent leather bum bag, studio |
| `mia-print.png` | Leopard backpack on stool, studio |
| `lina.png` | Studded silver bag |
| `yellow-sling.jpeg` | Yellow sling bag, outdoor columns |
| `black-editorial.jpeg` | Black bag, dramatic editorial background |
| `pink-metallic-bumbag.jpeg` | Pink metallic bum bag close-up |
| `black-shoulder-bag.jpeg` | Classic black shoulder bag, white bg |
| `street-tan-bag.jpeg` | Tan leather backpack, Buenos Aires street |
| `sophia-varias.jpeg` | Model holding multiple colorful bags |
| `olivia-rainbow.jpeg` | Two models, rainbow background |
| `olivia-pink-standing.jpeg` | Pink metallic backpack |
| `red-plaid-bag.jpeg` | Black bum bag, outdoor |
| `picnic-fanny-packs.jpeg` | Lifestyle — two women with fanny packs |
| `street-tan-closeup.jpeg` | Tan bag detail, street crossing |
| `bianca.png` / `bianca-street.jpeg` | Leopard backpack (reserve shots) |
