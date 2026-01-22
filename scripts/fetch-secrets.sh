#!/bin/bash
set -euo pipefail

# ============================================================================
# fetch-secrets.sh
#
# Retrieves R2 credentials from Bitwarden Secrets Manager for CI/CD workflows.
# Designed to safely export secrets without exposing them in logs.
# Follows the same pattern as ghost-stack infra-shell.sh.
#
# Usage:
#   CI mode (GitHub Actions):
#     ./scripts/fetch-secrets.sh --ci --export-github-env
#
#   Local testing:
#     ./scripts/fetch-secrets.sh
#
# Required environment variables:
#   BWS_ACCESS_TOKEN - Bitwarden Secrets Manager access token
# ============================================================================

# ----------------------------
# Flags / Modes
# ----------------------------
CI_MODE=false
EXPORT_GITHUB_ENV=false

usage() {
  cat <<'EOF'
Usage: fetch-secrets.sh [options]

Options:
  --ci                 Non-interactive mode. Requires BWS_ACCESS_TOKEN env var.
  --export-github-env  Write exported secrets to $GITHUB_ENV (GitHub Actions).
  -h, --help           Show help.

EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ci) CI_MODE=true; shift ;;
    --export-github-env) EXPORT_GITHUB_ENV=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
  esac
done

# In GitHub Actions, $GITHUB_ENV is the canonical cross-step export mechanism.
if [[ -n "${GITHUB_ENV:-}" ]]; then
  EXPORT_GITHUB_ENV=true
fi

# ============================================================================
# Bitwarden Secrets Manager Integration
# ============================================================================

check_bws_available() {
  command -v bws &> /dev/null
}

mask_value() {
  local value="$1"
  if [[ -n "${GITHUB_ACTIONS:-}" && -n "$value" ]]; then
    echo "::add-mask::$value"
  fi
}

# Retrieve a secret from Bitwarden Secrets Manager by secret id
# Usage: get_bws_secret <secret_id>
get_bws_secret() {
  local secret_id="$1"
  local value=""

  # bws output shape can vary by version. This implementation matches ghost-stack jq-based parsing.
  # We suppress stderr to avoid accidental log noise.
  value="$(bws secret get "$secret_id" 2>/dev/null | jq -r '.value // empty' 2>/dev/null || true)"

  printf "%s" "$value"
}

# Export a variable into current process and optionally into GitHub Actions environment file
# Usage: export_var <name> <value>
export_var() {
  local name="$1"
  local value="$2"

  # Export into current shell environment (useful for workstation / same-step usage)
  export "$name=$value"

  # For GitHub Actions: persist across steps without printing secrets
  if [[ "$EXPORT_GITHUB_ENV" == "true" ]]; then
    # Use the multiline-safe format to avoid edge cases with special characters/newlines
    {
      echo "${name}<<__GHO_EOF__"
      echo "${value}"
      echo "__GHO_EOF__"
    } >> "$GITHUB_ENV"
  fi
}

# ============================================================================
# Main
# ============================================================================

if ! check_bws_available; then
  echo "❌ Bitwarden Secrets Manager CLI (bws) not found." >&2
  echo "   Install from: https://github.com/bitwarden/sdk-sm/releases" >&2
  exit 1
fi

if [[ -z "${BWS_ACCESS_TOKEN:-}" ]]; then
  if [[ "$CI_MODE" == "true" ]]; then
    echo "❌ BWS_ACCESS_TOKEN not set in CI mode." >&2
    exit 1
  else
    printf "Enter your BWS machine account token: "
    IFS= read -rs BWS_ACCESS_TOKEN
    printf "\n"
    export BWS_ACCESS_TOKEN
  fi
else
  export BWS_ACCESS_TOKEN
fi

echo "Retrieving R2 credentials from Bitwarden Secrets Manager..."

# ============================================================================
# Retrieve secrets using hardcoded Bitwarden secret IDs
# These are the same credentials used by ghost-stack
# ============================================================================

# Retrieve into local variables (do not echo values)
R2_ACCESS_KEY_ID="$(get_bws_secret "9dfdf110-5a84-48c3-ad7e-b39b002afd6b")"
mask_value "$R2_ACCESS_KEY_ID"

R2_SECRET_ACCESS_KEY="$(get_bws_secret "f5d9794d-fd45-4dcb-9994-b39b002b5056")"
mask_value "$R2_SECRET_ACCESS_KEY"

CLOUDFLARE_ACCOUNT_ID="$(get_bws_secret "2fea4609-0d6b-4d8d-b9b5-b39b002de85b")"
mask_value "$CLOUDFLARE_ACCOUNT_ID"

echo "Successfully retrieved secrets from Bitwarden Secrets Manager"

# Validate secrets were retrieved
if [[ -z "$R2_ACCESS_KEY_ID" ]]; then
  echo "❌ Failed to retrieve R2_ACCESS_KEY_ID from Bitwarden" >&2
  exit 1
fi

if [[ -z "$R2_SECRET_ACCESS_KEY" ]]; then
  echo "❌ Failed to retrieve R2_SECRET_ACCESS_KEY from Bitwarden" >&2
  exit 1
fi

if [[ -z "$CLOUDFLARE_ACCOUNT_ID" ]]; then
  echo "❌ Failed to retrieve CLOUDFLARE_ACCOUNT_ID from Bitwarden" >&2
  exit 1
fi

# Construct R2 endpoint from account ID
R2_ENDPOINT="https://${CLOUDFLARE_ACCOUNT_ID}.r2.cloudflarestorage.com"

# Hardcoded R2 bucket name for sysext images
# Public URL: https://ghost-sysext-images.separationofconcerns.dev
R2_BUCKET="ghost-sysext-images"

# Export (and optionally write to $GITHUB_ENV) without printing values
export_var "R2_ACCESS_KEY_ID" "${R2_ACCESS_KEY_ID}"
export_var "R2_SECRET_ACCESS_KEY" "${R2_SECRET_ACCESS_KEY}"
export_var "R2_ENDPOINT" "${R2_ENDPOINT}"
export_var "R2_BUCKET" "${R2_BUCKET}"

echo "✅ R2 credentials and configuration exported successfully"
