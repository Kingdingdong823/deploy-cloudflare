# deploy-cloudflare

Reusable **Cloudflare Pages deploy + Access lockdown** for any static/SPA app.

One GitHub reusable workflow and shared scripts — no copying bash files into every repo.

## Quick start (new app)

### 1. Org secrets (once)

Set at **GitHub → Organization → Secrets** (or per-repo if you prefer):

| Secret | Purpose |
| ------ | ------- |
| `CLOUDFLARE_API_TOKEN` | Pages + Zero Trust + Access permissions |
| `CLOUDFLARE_ACCOUNT_ID` | Your Cloudflare account ID |
| `ALLOWED_EMAILS` | Default login allowlist (optional if set per workflow) |

```bash
gh secret set CLOUDFLARE_API_TOKEN --org YOUR_ORG
gh secret set CLOUDFLARE_ACCOUNT_ID --org YOUR_ORG --body "YOUR_ACCOUNT_ID"
gh secret set ALLOWED_EMAILS --org YOUR_ORG --body "you@example.com"
```

Per-repo: use `--repo YOUR_ORG/my-app` instead of `--org`.

### 2. Add workflow to your app repo

```yaml
# .github/workflows/deploy.yml
name: Deploy and secure

on:
  push:
    branches: [main]
  workflow_dispatch:

jobs:
  deploy:
    uses: Kingdingdong823/deploy-cloudflare/.github/workflows/pages-access.yml@v1
    secrets: inherit
    with:
      project_name: my-app
      access_domain: my-app.pages.dev
      # allowed_emails: you@example.com   # optional if ALLOWED_EMAILS secret is set
```

Defaults (omit `with:` entirely for convention-over-configuration):

| Input | Default |
| ----- | ------- |
| `project_name` | GitHub repository name |
| `access_domain` | `{project_name}.pages.dev` |
| `access_app_name` | Repository name |
| `build_command` | `npm ci && npm run build` |
| `dist_directory` | `dist` |
| `node_version` | `22` |
| `allowed_emails` | `ALLOWED_EMAILS` secret |

### 3. Push to `main`

Build → Pages deploy (creates project if missing) → Access allowlist + email OTP.

## One-time Cloudflare setup

1. [one.dash.cloudflare.com](https://one.dash.cloudflare.com/) — create Zero Trust team (free)
2. [API token](https://dash.cloudflare.com/profile/api-tokens) with:
   - Cloudflare Pages → Edit
   - Zero Trust → Edit
   - Access: Apps and Policies → Edit
   - Access: Organizations, Identity Providers, and Groups → Edit

## Local deploy (any app)

Install shared scripts once:

```bash
git clone https://github.com/Kingdingdong823/deploy-cloudflare.git ~/.local/share/cf-deploy
```

In your app, create `.env.cloudflare`:

```bash
CLOUDFLARE_API_TOKEN=...
CLOUDFLARE_ACCOUNT_ID=...
ALLOWED_EMAILS=you@example.com
CLOUDFLARE_PAGES_PROJECT=my-app
ACCESS_APP_DOMAIN=my-app.pages.dev
```

Deploy:

```bash
bash ~/.local/share/cf-deploy/scripts/deploy-pages-and-access.sh
```

Or set `CF_DEPLOY_HOME=~/.local/share/cf-deploy` and add to `package.json`:

```json
"deploy": "bash \"$CF_DEPLOY_HOME/scripts/deploy-pages-and-access.sh\""
```

Requires Node.js 22+, `curl`, `jq`, and project build output in `dist/` (override with `DIST_DIRECTORY`).

## Tagging releases

Pin apps to a stable version:

```yaml
uses: Kingdingdong823/deploy-cloudflare/.github/workflows/pages-access.yml@v1
```

## License

MIT
