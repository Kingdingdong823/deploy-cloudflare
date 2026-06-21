#!/usr/bin/env bash
# Create or update a Cloudflare Access app (email allowlist + optional OTP).
# Env: CLOUDFLARE_API_TOKEN, CLOUDFLARE_ACCOUNT_ID, ALLOWED_EMAILS,
#      ACCESS_APP_DOMAIN, ACCESS_APP_NAME, ENABLE_EMAIL_OTP

set -euo pipefail

APP_ROOT="${APP_ROOT:-$(pwd)}"
ENV_FILE="${ENV_FILE:-$APP_ROOT/.env.cloudflare}"

if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  set -a && source "$ENV_FILE" && set +a
fi

API="https://api.cloudflare.com/client/v4"
TOKEN="${CLOUDFLARE_API_TOKEN:-}"
ACCOUNT_ID="${CLOUDFLARE_ACCOUNT_ID:-}"
PROJECT="${CLOUDFLARE_PAGES_PROJECT:-}"
DOMAIN="${ACCESS_APP_DOMAIN:-}"
[[ -z "$DOMAIN" && -n "$PROJECT" ]] && DOMAIN="${PROJECT}.pages.dev"
[[ -z "$DOMAIN" ]] && DOMAIN="app.pages.dev"
APP_NAME="${ACCESS_APP_NAME:-${PROJECT:-App}}"
EMAILS="${ALLOWED_EMAILS:-}"
ENABLE_EMAIL_OTP="${ENABLE_EMAIL_OTP:-true}"

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required (brew install jq)" >&2
  exit 1
fi

if [[ -z "$TOKEN" ]]; then
  echo "error: set CLOUDFLARE_API_TOKEN" >&2
  exit 1
fi

if [[ -z "$ACCOUNT_ID" ]]; then
  ACCOUNT_ID="$(curl -fsS "$API/accounts" \
    -H "Authorization: Bearer $TOKEN" \
    | jq -r '.result[0].id // empty')"
fi

if [[ -z "$ACCOUNT_ID" || "$ACCOUNT_ID" == "null" ]]; then
  echo "error: set CLOUDFLARE_ACCOUNT_ID or fix API token permissions" >&2
  exit 1
fi

if [[ -z "$EMAILS" ]]; then
  echo "error: set ALLOWED_EMAILS (comma-separated)" >&2
  exit 1
fi

auth_header=(-H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json")
CF_HTTP_STATUS=""
CF_HTTP_BODY=""

cf_request() {
  local method="$1" url="$2"
  shift 2
  local tmp
  tmp="$(mktemp)"
  CF_HTTP_STATUS="$(curl -sS -o "$tmp" -w "%{http_code}" -X "$method" "$url" "${auth_header[@]}" "$@")"
  CF_HTTP_BODY="$(cat "$tmp")"
  rm -f "$tmp"
}

access_forbidden_help() {
  cat >&2 <<'EOF'
error: Cloudflare Access API returned 403.

Usually one of:
  1. Zero Trust not set up — open https://one.dash.cloudflare.com once and create a team (free).
  2. API token missing permissions — recreate with Pages + Zero Trust + Access permissions.
  3. Update CLOUDFLARE_API_TOKEN, then re-run deploy.
EOF
}

if [[ "$ENABLE_EMAIL_OTP" == "true" ]]; then
  echo "Ensuring One-time PIN (email code) login is enabled..."
  cf_request GET "$API/accounts/$ACCOUNT_ID/access/identity_providers"

  if [[ "$CF_HTTP_STATUS" == "403" ]]; then
    echo "warning: cannot list identity providers (403) — skipping OTP auto-setup." >&2
  elif [[ "$CF_HTTP_STATUS" != "200" ]]; then
    echo "warning: identity providers API returned HTTP $CF_HTTP_STATUS — skipping OTP setup." >&2
  else
    OTP_EXISTS="$(echo "$CF_HTTP_BODY" | jq -r '[.result[]? | select(.type == "onetimepin")] | length')"
    if [[ "$OTP_EXISTS" == "0" ]]; then
      cf_request POST "$API/accounts/$ACCOUNT_ID/access/identity_providers" \
        --data '{"name":"One-time PIN login","type":"onetimepin","config":{}}'
      if [[ "$CF_HTTP_STATUS" == "200" && "$(echo "$CF_HTTP_BODY" | jq -r '.success')" == "true" ]]; then
        echo "One-time PIN enabled."
      else
        echo "warning: could not enable One-time PIN (HTTP $CF_HTTP_STATUS):" >&2
        echo "$CF_HTTP_BODY" | jq '.' >&2 || true
      fi
    else
      echo "One-time PIN already enabled."
    fi
  fi
  echo ""
fi

INCLUDE_JSON="$(printf '%s' "$EMAILS" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$' \
  | jq -R . | jq -s 'map({email: {email: .}})')"

PAYLOAD="$(jq -n \
  --arg name "$APP_NAME" \
  --arg domain "$DOMAIN" \
  --argjson include "$INCLUDE_JSON" \
  '{
    name: $name,
    type: "self_hosted",
    domain: $domain,
    session_duration: "168h",
    policies: [
      {
        name: "Allowlist",
        decision: "allow",
        precedence: 1,
        include: $include
      }
    ]
  }')"

echo "Account:  $ACCOUNT_ID"
echo "Domain:   $DOMAIN"
echo "Allow:    $EMAILS"
echo ""

cf_request GET "$API/accounts/$ACCOUNT_ID/access/apps?per_page=50"

if [[ "$CF_HTTP_STATUS" == "403" ]]; then
  access_forbidden_help
  exit 1
fi

EXISTING_ID="$(echo "$CF_HTTP_BODY" | jq -r --arg domain "$DOMAIN" '.result[]? | select(.domain == $domain or (.self_hosted_domains[]? == $domain)) | .id' \
  | head -1)"

if [[ -n "$EXISTING_ID" ]]; then
  echo "Updating existing Access app $EXISTING_ID..."
  cf_request PUT "$API/accounts/$ACCOUNT_ID/access/apps/$EXISTING_ID" --data "$PAYLOAD"
else
  echo "Creating Access app..."
  cf_request POST "$API/accounts/$ACCOUNT_ID/access/apps" --data "$PAYLOAD"
fi

RESPONSE="$CF_HTTP_BODY"

if [[ "$CF_HTTP_STATUS" == "403" ]]; then
  access_forbidden_help
  exit 1
fi

if [[ "$(echo "$RESPONSE" | jq -r '.success')" != "true" ]]; then
  echo "error: Cloudflare API failed:" >&2
  echo "$RESPONSE" | jq '.' >&2
  exit 1
fi

APP_ID="$(echo "$RESPONSE" | jq -r '.result.id')"
echo ""
echo "Done. Access app id: $APP_ID"
echo "Protected URL: https://$DOMAIN"
