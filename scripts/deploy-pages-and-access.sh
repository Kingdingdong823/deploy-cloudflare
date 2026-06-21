#!/usr/bin/env bash
# Build (optional), deploy to Cloudflare Pages, apply Access allowlist.
#
# Env: CLOUDFLARE_PAGES_PROJECT, ACCESS_APP_DOMAIN, ALLOWED_EMAILS,
#      BUILD_COMMAND (default: npm run build), DIST_DIRECTORY (default: dist),
#      SKIP_BUILD=true to skip build step

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_ROOT="${APP_ROOT:-$(pwd)}"
cd "$APP_ROOT"

if [[ -f "$APP_ROOT/.env.cloudflare" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$APP_ROOT/.env.cloudflare"
  set +a
fi

PROJECT="${CLOUDFLARE_PAGES_PROJECT:-}"
[[ -z "$PROJECT" ]] && PROJECT="$(basename "$APP_ROOT")"
DIST="${DIST_DIRECTORY:-dist}"
BUILD="${BUILD_COMMAND:-npm run build}"
DOMAIN="${ACCESS_APP_DOMAIN:-${PROJECT}.pages.dev}"

if [[ "${SKIP_BUILD:-false}" != "true" ]]; then
  echo "==> Building ($BUILD)"
  eval "$BUILD"
fi

if [[ ! -d "$DIST" ]]; then
  echo "error: dist directory not found: $DIST" >&2
  exit 1
fi

echo ""
echo "==> Ensuring Cloudflare Pages project exists ($PROJECT)"
if ! npx wrangler pages project list 2>/dev/null | grep -qw "$PROJECT"; then
  echo "    Creating project (first deploy)"
  npx wrangler pages project create "$PROJECT" --production-branch=main
fi

echo ""
echo "==> Deploying to Cloudflare Pages (project: $PROJECT)"
npx wrangler pages deploy "$DIST" --project-name="$PROJECT"

echo ""
echo "==> Applying Cloudflare Access"
export CLOUDFLARE_PAGES_PROJECT="$PROJECT"
export ACCESS_APP_DOMAIN="$DOMAIN"
if ! bash "$SCRIPT_DIR/setup-cloudflare-access.sh"; then
  echo ""
  echo "Pages deploy succeeded, but Access lockdown failed."
  exit 1
fi

echo ""
echo "All done. Open https://$DOMAIN in a private window to test login."
