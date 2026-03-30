#!/usr/bin/env bash
# Creates a PR to update the Alloy sysext version and hash in a target repository.
#
# Required environment variables:
#   GH_TOKEN    - GitHub token with repo access
#   VERSION     - New Alloy version (e.g., 1.14.2)
#   HASH        - SHA256 hash of the new sysext image
#
# Usage:
#   create-update-pr.sh <repo> <file_path> <base_branch>
#
# Examples:
#   create-update-pr.sh noahwhite/ghost-stack opentofu/modules/vultr/instance/userdata/ghost.bu develop
#   create-update-pr.sh officina-pub/infisical-stack opentofu/modules/server/userdata/infisical.bu.tftpl main

set -euo pipefail

REPO="${1:?Usage: create-update-pr.sh <repo> <file_path> <base_branch>}"
FILE_PATH="${2:?Usage: create-update-pr.sh <repo> <file_path> <base_branch>}"
BASE_BRANCH="${3:?Usage: create-update-pr.sh <repo> <file_path> <base_branch>}"

: "${VERSION:?VERSION must be set}"
: "${HASH:?HASH must be set}"
: "${GH_TOKEN:?GH_TOKEN must be set}"

BRANCH="feature/update-alloy-sysext-to-${VERSION}"
FILE_NAME=$(basename "${FILE_PATH}")

echo "=== Creating ${REPO} PR for Alloy ${VERSION} ==="

# Get the SHA of the base branch
BASE_SHA=$(gh api "repos/${REPO}/git/ref/heads/${BASE_BRANCH}" --jq '.object.sha')
echo "Base branch (${BASE_BRANCH}) SHA: ${BASE_SHA}"

# Delete branch if it already exists (from previous failed attempt)
echo "Checking if branch ${BRANCH} already exists..."
if gh api "repos/${REPO}/git/refs/heads/${BRANCH}" --silent 2>/dev/null; then
  echo "Branch exists, deleting it..."
  gh api "repos/${REPO}/git/refs/heads/${BRANCH}" --method DELETE
fi

# Create feature branch from base branch
echo "Creating branch ${BRANCH}..."
gh api "repos/${REPO}/git/refs" \
  --method POST \
  --field ref="refs/heads/${BRANCH}" \
  --field sha="${BASE_SHA}"

# Get current file content and SHA
echo "Fetching current ${FILE_NAME}..."
FILE_RESPONSE=$(gh api "repos/${REPO}/contents/${FILE_PATH}?ref=${BASE_BRANCH}")
FILE_SHA=$(echo "$FILE_RESPONSE" | jq -r '.sha')
CURRENT_CONTENT=$(echo "$FILE_RESPONSE" | jq -r '.content' | base64 -d)

# Extract current version
CURRENT_VERSION=$(echo "$CURRENT_CONTENT" | grep -oP 'alloy-\K[0-9]+\.[0-9]+\.[0-9]+(?=-amd64\.raw)' | head -1)

if [ -z "${CURRENT_VERSION}" ]; then
  echo "No Alloy sysext found in ${FILE_NAME}, skipping"
  exit 0
fi

# Extract the current Alloy hash
CURRENT_HASH=$(echo "$CURRENT_CONTENT" | grep -A3 "ghost-sysext-images.separationofconcerns.dev/alloy-" | grep -oP 'sha256-\K[a-f0-9]{64}' | head -1)

if [ -z "${CURRENT_HASH}" ]; then
  echo "ERROR: Could not find current Alloy hash in ${FILE_NAME}"
  exit 1
fi

echo "Current version: ${CURRENT_VERSION}, hash: ${CURRENT_HASH}"
echo "New version: ${VERSION}, hash: ${HASH}"

# Check if version AND hash are already current
if [ "${CURRENT_VERSION}" = "${VERSION}" ] && [ "${CURRENT_HASH}" = "${HASH}" ]; then
  echo "✓ Version ${VERSION} with same hash is already in ${FILE_NAME}, skipping PR creation"
  exit 0
fi

if [ "${CURRENT_VERSION}" = "${VERSION}" ]; then
  echo "Same version but different hash - creating PR to update hash"
else
  echo "Updating from ${CURRENT_VERSION} to ${VERSION}"
fi

# Update the content - only replace the specific Alloy hash, not all hashes
NEW_CONTENT=$(echo "$CURRENT_CONTENT" | sed "s/alloy-${CURRENT_VERSION}-amd64\.raw/alloy-${VERSION}-amd64.raw/g")
NEW_CONTENT=$(echo "$NEW_CONTENT" | sed "s/sha256-${CURRENT_HASH}/sha256-${HASH}/g")

# Verify changes were made
if ! echo "$NEW_CONTENT" | grep -q "alloy-${VERSION}-amd64.raw"; then
  echo "ERROR: Version update failed"
  exit 1
fi

if ! echo "$NEW_CONTENT" | grep -q "sha256-${HASH}"; then
  echo "ERROR: Hash update failed"
  exit 1
fi

echo "✓ ${FILE_NAME} content updated successfully"

# Base64 encode the new content
NEW_CONTENT_B64=$(echo "$NEW_CONTENT" | base64 -w 0)

# Update file via API (creates a verified commit signed by GitHub)
echo "Committing changes via GitHub API..."
gh api "repos/${REPO}/contents/${FILE_PATH}" \
  --method PUT \
  --field message="chore: update Grafana Alloy sysext to ${VERSION}" \
  --field content="${NEW_CONTENT_B64}" \
  --field sha="${FILE_SHA}" \
  --field branch="${BRANCH}"

echo "✓ Commit created (verified by GitHub)"

# Create PR
echo "Creating pull request..."
printf -v PR_BODY '%s\n' \
  "## Summary" \
  "" \
  "- Updates Grafana Alloy sysext from ${CURRENT_VERSION} to ${VERSION}" \
  "- Updates SHA256 hash to \`${HASH}\`" \
  "" \
  "## Automated PR" \
  "" \
  "This PR was automatically created by the alloy-sysext-build CI pipeline." \
  "" \
  "## Test plan" \
  "" \
  "- [ ] Review the version and hash changes in ${FILE_NAME}" \
  "- [ ] Merge PR to trigger deployment" \
  "- [ ] Verify Alloy version on instance: \`alloy --version\`" \
  "- [ ] Verify Alloy service status: \`systemctl status alloy\`" \
  "" \
  "## Related" \
  "" \
  "- [Alloy Release](https://github.com/grafana/alloy/releases/tag/v${VERSION})" \
  "- [Sysext Image](https://ghost-sysext-images.separationofconcerns.dev/alloy-${VERSION}-amd64.raw)"

PR_URL=$(gh pr create \
  --repo "${REPO}" \
  --base "${BASE_BRANCH}" \
  --head "${BRANCH}" \
  --title "Update Grafana Alloy sysext to ${VERSION}" \
  --body "${PR_BODY}")

echo "PR created: ${PR_URL}"

# Assign PR to Noah White
PR_NUMBER=$(echo "${PR_URL}" | grep -oP 'pull/\K\d+')
gh api "repos/${REPO}/issues/${PR_NUMBER}" \
  --method PATCH \
  --field assignees[]="noahwhite"

echo "=== ${REPO} PR created and assigned ==="
