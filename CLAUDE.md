# CLAUDE.md - Project Context for Claude Code

## Role

You are a staff-level infrastructure and application engineer/architect. Provide thorough, well-reasoned solutions with attention to security, maintainability, and operational excellence.

## Communication Standards

- All commit messages should be clear and descriptive
- All PR comments must be formatted in markdown
- Use todo lists to track multi-step tasks
- **Never add "Generated with Claude Code" or similar attribution lines to PRs or commits**
- **Never add Co-Authored-By lines to commits**
- **Always create PRs instead of committing directly to main or protected branches**
- **Always assign PRs to Noah White**

## Linear Integration

- Use the `ghost-stack` team for all issues and projects
- Include detailed acceptance criteria in issue descriptions
- Link related issues using dependencies where applicable
- Prefix user stories with `[User Story]` and spikes with `[Spike]`

## Project Overview

This repository provides automated build tooling to package Grafana Alloy as a systemd-sysext image for Flatcar Container Linux. The built images are published to Cloudflare R2 and consumed by the ghost-stack infrastructure.

## Key Technologies

- **systemd-sysext**: System extension images for Flatcar Container Linux
- **squashfs**: Image format for sysext images
- **GitHub Actions**: CI/CD for building and publishing images
- **Cloudflare R2**: Object storage for published images
- **Bitwarden Secrets Manager**: Secrets management via `bws` CLI

## Repository Structure

```
.github/workflows/
  build-and-publish.yml     # CI/CD pipeline for building and publishing sysext images
  check-new-releases.yml    # Daily check for new Alloy releases
scripts/
  fetch-secrets.sh          # Retrieves R2 credentials from Bitwarden
Dockerfile                  # Build container image
build-alloy-sysext.sh       # Main build script
```

## CI/CD Workflows

### End-to-End Automation Flow

When a new Grafana Alloy version is released upstream, the following automated sequence occurs:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         AUTOMATED UPDATE PIPELINE                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  1. check-new-releases.yml (daily at midnight UTC)                          │
│     ├── Detects new Alloy release from grafana/alloy                        │
│     ├── Triggers build-and-publish.yml via workflow_dispatch                │
│     └── Creates tracking issue in this repo → syncs to Linear               │
│                                                                             │
│  2. build-and-publish.yml                                                   │
│     ├── Builds sysext image in Docker container                             │
│     ├── Signs image with GPG (creates .asc signature)                       │
│     ├── Uploads to Cloudflare R2 bucket                                     │
│     ├── Creates release tag (e.g., v1.13.0)                                 │
│     └── Creates PR in ghost-stack to update ghost.bu                        │
│                                                                             │
│  3. ghost-stack PR (auto-created)                                           │
│     ├── Branch: feature/update-alloy-sysext-to-{VERSION}                    │
│     ├── Updates Alloy version and SHA256 hash in ghost.bu                   │
│     └── Assigned to Noah White for review                                   │
│                                                                             │
│  4. After PR merge and deployment                                           │
│     ├── Instance is recreated with new Alloy version                        │
│     └── systemd-sysupdate configured for future auto-updates                │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### build-and-publish.yml

Builds, validates, signs, and publishes sysext images:

**Build Phase:**
1. Builds a Docker container with build tools
2. Runs `build-alloy-sysext.sh` to create the sysext image
3. Validates the image structure (binary, systemd service, extension-release)
4. Generates SHA256 checksums

**Sign Phase:**
5. Imports GPG private key from `GPG_PRIVATE_KEY` secret
6. Creates detached signatures (`.asc` files) for all `.raw` images

**Manifest Phase:**
7. Updates `SHA256SUMS` manifest in this repo (add/update entry for current version)
8. Signs manifest with GPG to create `SHA256SUMS.gpg`
9. Commits both files to main branch via GitHub Contents API (verified commits)

**Publish Phase:**
10. Retrieves R2 credentials from Bitwarden via `fetch-secrets.sh`
11. Uploads images, checksums, signatures, and manifest files to Cloudflare R2 bucket
12. Creates release tag in this repo (for workflow_dispatch triggers only)

**Ghost-Stack Integration:**
13. Generates GitHub App token for ghost-stack access
14. Creates feature branch `feature/update-alloy-sysext-to-{VERSION}`
15. Updates ghost.bu with new version and hash
16. Creates PR and assigns to Noah White

**Skip Logic:**
- For `workflow_dispatch`: Skips if release tag already exists AND hash matches
- For `release` events: Always proceeds (the release is what we're building)
- Compares both version AND hash to handle same-version rebuilds (e.g., after enabling GPG signing)

**Triggered by:**
- GitHub release (extracts version from tag)
- Manual workflow dispatch (specify version)
- Automated trigger from check-new-releases.yml

### check-new-releases.yml

Automated version detection that runs daily:

1. Gets current built version from latest release tag in this repo
2. Checks latest stable Alloy release from GitHub API (excludes prereleases)
3. Compares versions using `sort -V`
4. If new version available:
   - Triggers build-and-publish.yml via workflow_dispatch
   - Creates a tracking issue (syncs to Linear via GitHub integration)

**Triggered by:**
- Daily cron schedule (midnight UTC)
- Manual workflow dispatch (with optional dry-run mode)

**Note:** The release tag is created by build-and-publish.yml after successful upload, not by this workflow. This prevents race conditions where the release exists but artifacts don't.

## Linear-GitHub Integration

GitHub issues created in this repository are automatically synced to Linear under the ghost-stack team. This provides:

- Automatic tracking issues for each Alloy version build
- Visibility into build status from Linear
- Linked PRs and commits

The tracking issues created by check-new-releases.yml will appear as Linear stories.

## Secrets Management

### GitHub Repository Secrets

| Secret | Purpose | How to Set |
|--------|---------|------------|
| `BWS_ACCESS_TOKEN` | Bitwarden Secrets Manager access | From Bitwarden admin console |
| `APP_ID` | GitHub App ID for alloy-sysext-automation | From GitHub App settings page |
| `APP_PRIVATE_KEY` | GitHub App private key (PEM format) | Generated from GitHub App settings |
| `GPG_PRIVATE_KEY` | Base64-encoded GPG private key for signing | Generated locally, base64 encoded |

**Listing current secrets:**
```bash
gh secret list --repo noahwhite/alloy-sysext-build
```

### R2 Credentials

R2 credentials are retrieved at runtime from Bitwarden Secrets Manager (not stored in GitHub). This provides:
- Centralized credential management
- Easier rotation without updating GitHub secrets
- Audit trail via Bitwarden

The `fetch-secrets.sh` script retrieves and exports:
- `R2_ACCESS_KEY_ID`
- `R2_SECRET_ACCESS_KEY`
- `R2_BUCKET`
- `R2_ENDPOINT`

## GPG Signing

### Overview

Sysext images are signed with GPG to enable cryptographic verification by systemd-sysupdate on the target systems. This ensures only authentic images from this CI pipeline can be installed.

**Architecture:**
```
┌─────────────────────┐     ┌─────────────────────┐     ┌─────────────────────┐
│  alloy-sysext-build │     │    Cloudflare R2    │     │   ghost-stack       │
│  (CI Pipeline)      │     │    (Storage)        │     │   (Instance)        │
├─────────────────────┤     ├─────────────────────┤     ├─────────────────────┤
│ GPG Private Key     │────▶│ alloy-X.raw         │────▶│ GPG Public Key      │
│ (GitHub Secret)     │     │ alloy-X.raw.asc     │     │ (merged into        │
│                     │     │ alloy-X.raw.sha256  │     │  import-pubring.gpg)│
│                     │     │ SHA256SUMS          │     │                     │
│                     │     │ SHA256SUMS.gpg      │     │                     │
└─────────────────────┘     └─────────────────────┘     └─────────────────────┘
        │                           │                           │
        │ Signs images              │ Stores signed             │ Verifies
        │ + manifest                │ artifacts                 │ signatures
        └───────────────────────────┴───────────────────────────┘
```

**Key Details:**
- **Algorithm:** RSA 4096-bit
- **Expiration:** None (rotate manually as needed)
- **Identity:** `Alloy Sysext Signing Key <alloy-sysext@separationofconcerns.dev>`
- **Passphrase:** None (safe for CI - key only accessible via GitHub Secrets)

### Security Considerations

**Why no passphrase?**
- The private key is stored as a GitHub Secret, which is already encrypted at rest
- CI environments can't interactively enter passphrases
- The key is only used in ephemeral CI runners, not on persistent systems

**Why this is safe:**
- Only repository maintainers can trigger workflows
- GitHub Secrets are not exposed in logs or to forks
- The public repository doesn't contain the private key
- Workflow modifications require PR review

### Initial Setup: Generating the GPG Key

```bash
# Generate a new GPG key (single command, no heredoc issues)
gpg --batch --passphrase '' --quick-gen-key \
  "Alloy Sysext Signing Key <alloy-sysext@separationofconcerns.dev>" \
  rsa4096 sign never

# Verify the key was created
gpg --list-secret-keys --keyid-format LONG

# Export the private key (base64-encoded for GitHub secret)
gpg --armor --export-secret-keys alloy-sysext@separationofconcerns.dev | base64 -w 0 > gpg-private-key.b64

# Export the public key (for deployment to ghost-stack)
gpg --armor --export alloy-sysext@separationofconcerns.dev > alloy-sysext-signing.pub

# Securely delete the private key file after adding to GitHub
# (keep the public key for ghost-stack deployment)
```

### Adding the GPG Secret to GitHub

```bash
# Method 1: Pipe directly (recommended)
gpg --armor --export-secret-keys alloy-sysext@separationofconcerns.dev | \
  base64 -w 0 | \
  gh secret set GPG_PRIVATE_KEY --repo noahwhite/alloy-sysext-build

# Method 2: From file
gh secret set GPG_PRIVATE_KEY --repo noahwhite/alloy-sysext-build < gpg-private-key.b64

# Verify the secret exists
gh secret list --repo noahwhite/alloy-sysext-build
```

### Deploying the Public Key to ghost-stack

The public key is deployed via Ignition to `/etc/systemd/alloy-sysext.gpg.pub` on ghost-stack instances. At boot, a service merges this with system vendor keys into the global keyring at `/etc/systemd/import-pubring.gpg`.

**Location in ghost-stack:** `opentofu/modules/vultr/instance/userdata/ghost.bu`

**Key files on instance:**
- `/etc/systemd/alloy-sysext.gpg.pub` - Alloy signing public key (deployed via Ignition)
- `/usr/lib/systemd/import-pubring.gpg` - System vendor keys (read-only, from OS)
- `/etc/systemd/import-pubring.gpg` - Merged keyring (generated at boot)

The public key is embedded inline in the Butane file. To update:

1. Export the public key:
   ```bash
   gpg --armor --export alloy-sysext@separationofconcerns.dev
   ```

2. Replace the key content in ghost.bu under the `alloy-sysext.gpg.pub` file entry

3. Create a PR and deploy

### Key Rotation Procedure

**When to rotate:**
- If the private key is suspected to be compromised
- As part of regular security hygiene (annually recommended)
- When changing the signing identity

**Rotation Steps:**

1. **Generate new key pair:**
   ```bash
   gpg --batch --passphrase '' --quick-gen-key \
     "Alloy Sysext Signing Key <alloy-sysext@separationofconcerns.dev>" \
     rsa4096 sign never
   ```

2. **Update GitHub secret:**
   ```bash
   gpg --armor --export-secret-keys alloy-sysext@separationofconcerns.dev | \
     base64 -w 0 | \
     gh secret set GPG_PRIVATE_KEY --repo noahwhite/alloy-sysext-build
   ```

3. **Update ghost-stack with new public key:**
   - Export: `gpg --armor --export alloy-sysext@separationofconcerns.dev`
   - Update ghost.bu with new key content
   - Create PR and merge

4. **Deploy ghost-stack:**
   - Run `tofu apply` to recreate instance with new public key
   - New instance will trust both old (cached) and new signatures

5. **Trigger a new build** to create newly signed images:
   ```bash
   gh workflow run build-and-publish.yml --repo noahwhite/alloy-sysext-build \
     -f version=<current-version>
   ```

6. **Delete old key from local keyring:**
   ```bash
   gpg --delete-secret-keys <old-key-id>
   gpg --delete-keys <old-key-id>
   ```

**Note:** During rotation, there's a brief window where the instance has the old public key but R2 has newly signed images. The next `tofu apply` resolves this.

## SHA256SUMS Manifest

### Overview

systemd-sysupdate with `Verify=true` requires a `SHA256SUMS` manifest to discover available versions and verify downloads. The manifest is stored in this repository and uploaded to R2 alongside the sysext images.

**Files:**
- `SHA256SUMS` - Standard sha256sum format listing all available versions
- `SHA256SUMS.gpg` - Detached GPG signature for manifest verification

**Format:**
```
<64-char-sha256-hash>  <filename>
```

**Example:**
```
abc123...def  alloy-1.14.0-amd64.raw
789xyz...456  alloy-1.14.1-amd64.raw
```

### How systemd-sysupdate Uses the Manifest

1. Fetches `<Path>/SHA256SUMS` from the configured URL
2. Verifies signature against `<Path>/SHA256SUMS.gpg` using system keyring
3. Parses filenames with `MatchPattern` to extract available versions
4. Downloads matching files and verifies against listed hashes

### Build Pipeline Integration

The manifest is updated automatically during each build:

1. **Update Entry**: Existing entry for the version is replaced (handles rebuilds)
2. **Sort Versions**: Entries sorted by version number for readability
3. **Sign Manifest**: GPG signs the manifest to create `SHA256SUMS.gpg`
4. **Commit to Repo**: Uses GitHub Contents API for verified commits
5. **Upload to R2**: Both files uploaded alongside the sysext image

**Note:** The workflow uses `concurrency: alloy-sysext-build` to serialize builds and prevent race conditions when updating the manifest.

### Verified Commits

The SHA256SUMS commit uses the GitHub App token with the Contents API, which creates commits that are automatically verified by GitHub. This is necessary because:
- Branch protection requires signed commits
- Branch protection requires changes via PR (Contents API bypasses this for app commits)
- Commits appear with the "Verified" badge in GitHub

### GPG Keyring on Ghost Instances

systemd-sysupdate uses a global keyring at `/etc/systemd/import-pubring.gpg`. The ghost-stack configures a merge service that:

1. Copies system vendor keys from `/usr/lib/systemd/import-pubring.gpg` (if present)
2. Appends the Alloy signing public key
3. Writes merged keyring to `/etc/systemd/import-pubring.gpg`

This preserves vendor keys (Flatcar, Ubuntu, etc.) while adding the Alloy key for signature verification.

**Service:** `sysupdate-import-pubring.service` runs before any systemd-sysupdate service.

### Manual Manifest Operations

**View current manifest:**
```bash
curl -s https://ghost-sysext-images.separationofconcerns.dev/SHA256SUMS
```

**Verify manifest signature:**
```bash
curl -sO https://ghost-sysext-images.separationofconcerns.dev/SHA256SUMS
curl -sO https://ghost-sysext-images.separationofconcerns.dev/SHA256SUMS.gpg
gpg --verify SHA256SUMS.gpg SHA256SUMS
```

**Add entry manually (if needed):**
```bash
# Get hash
HASH=$(curl -s https://ghost-sysext-images.separationofconcerns.dev/alloy-X.Y.Z-amd64.raw.sha256 | awk '{print $1}')

# Add to manifest
echo "${HASH}  alloy-X.Y.Z-amd64.raw" >> SHA256SUMS
sort -t'-' -k2 -V SHA256SUMS -o SHA256SUMS

# Re-sign
gpg --armor --detach-sign SHA256SUMS
mv SHA256SUMS.asc SHA256SUMS.gpg
```

### GitHub App: alloy-sysext-automation

The workflow uses a GitHub App to create PRs in ghost-stack with verified commits. This is preferred over a PAT because:
- Commits are signed/verified by GitHub automatically
- No token expiration to manage
- Granular permissions scoped to specific repositories
- Actions performed are attributed to the app, not a user

**App Configuration:**
- **App Name:** alloy-sysext-automation
- **App URL:** https://github.com/apps/alloy-sysext-automation
- **Owner:** noahwhite
- **Installed on:** noahwhite/ghost-stack

**Permissions Required:**
| Permission | Access | Purpose |
|------------|--------|---------|
| Contents | Read & Write | Create branches and commits |
| Pull requests | Read & Write | Create and update PRs |
| Metadata | Read | Required for API access |

### Creating the GitHub App

1. Go to https://github.com/settings/apps/new
2. Fill in:
   - **App name:** `alloy-sysext-automation`
   - **Homepage URL:** `https://github.com/noahwhite/alloy-sysext-build`
   - **Webhook:** Uncheck "Active" (not needed)
3. Set permissions:
   - Repository permissions → Contents: Read & Write
   - Repository permissions → Pull requests: Read & Write
   - Repository permissions → Metadata: Read
4. Select "Only on this account"
5. Click "Create GitHub App"
6. Note the **App ID** displayed on the app settings page
7. Generate a private key (see below)
8. Install the app on the ghost-stack repository

### Generating the Private Key

1. Go to https://github.com/settings/apps/alloy-sysext-automation
2. Scroll to "Private keys" section
3. Click "Generate a private key"
4. A `.pem` file will be downloaded
5. Store the entire PEM content (including BEGIN/END lines) as the `APP_PRIVATE_KEY` secret

### Adding Secrets to Repository

```bash
# Using GitHub CLI
gh secret set APP_ID --repo noahwhite/alloy-sysext-build
# Enter the numeric App ID when prompted

gh secret set APP_PRIVATE_KEY --repo noahwhite/alloy-sysext-build < path/to/private-key.pem
```

Or via GitHub UI:
1. Go to https://github.com/noahwhite/alloy-sysext-build/settings/secrets/actions
2. Click "New repository secret"
3. Add `APP_ID` with the numeric App ID value
4. Add `APP_PRIVATE_KEY` with the full PEM file contents

### Rotating the Private Key

Private keys don't expire, but should be rotated if compromised or as part of security hygiene.

**Rotation Procedure:**

1. **Generate new key:**
   - Go to https://github.com/settings/apps/alloy-sysext-automation
   - Scroll to "Private keys"
   - Click "Generate a private key"
   - Download the new `.pem` file

2. **Update the secret:**
   ```bash
   gh secret set APP_PRIVATE_KEY --repo noahwhite/alloy-sysext-build < new-private-key.pem
   ```

3. **Verify the workflow works:**
   - Trigger a manual workflow run to test
   - Verify a PR is created in ghost-stack with a verified commit

4. **Revoke the old key:**
   - Go to https://github.com/settings/apps/alloy-sysext-automation
   - Find the old key in "Private keys" section
   - Click "Revoke" next to the old key

**Note:** You can have multiple active private keys during rotation, allowing zero-downtime key rotation.

### Troubleshooting

**"Resource not accessible by integration" error:**
- The app may not be installed on the target repository
- Go to https://github.com/settings/apps/alloy-sysext-automation/installations
- Ensure ghost-stack is in the list of installed repositories

**"Bad credentials" error:**
- The private key may be incorrectly formatted
- Ensure the entire PEM content is stored, including `-----BEGIN RSA PRIVATE KEY-----` and `-----END RSA PRIVATE KEY-----` lines
- Check for trailing newlines or whitespace issues

**Commits not showing as verified:**
- This shouldn't happen with the GitHub App approach
- Verify the commit was made via the Contents API, not git push

## Building Locally

```bash
# Build the container
docker build -t alloy-sysext-builder .

# Run the build
mkdir -p output
docker run --rm \
  -v "${PWD}/output:/output" \
  -v "${PWD}/build-alloy-sysext.sh:/build/build-alloy-sysext.sh:ro" \
  -e VERSION="1.10.2" \
  alloy-sysext-builder \
  /build/build-alloy-sysext.sh
```

## Output Files

```
output/
  alloy-{VERSION}-amd64.raw          # Sysext image
  alloy-{VERSION}-amd64.raw.sha256   # Checksum
  alloy-{VERSION}-amd64.raw.asc      # GPG signature
  alloy-{VERSION}.raw                # Compatibility symlink
  alloy-{VERSION}.raw.sha256         # Checksum
  alloy-{VERSION}.raw.asc            # GPG signature
```

## Troubleshooting

### GPG Signing Errors

**"gpg: no valid OpenPGP data found"**
- The `GPG_PRIVATE_KEY` secret is empty or incorrectly formatted
- Re-export and re-add the secret:
  ```bash
  gpg --armor --export-secret-keys alloy-sysext@separationofconcerns.dev | \
    base64 -w 0 | \
    gh secret set GPG_PRIVATE_KEY --repo noahwhite/alloy-sysext-build
  ```

**"gpg: signing failed: No secret key"**
- The key ID extraction failed or key wasn't imported correctly
- Check that the base64 decoding produces valid PGP data

### Build Skipped Unexpectedly

**"Release vX.Y.Z already exists, skipping build"**
- For `workflow_dispatch`: A release tag already exists
- This is correct behavior - use a release event to rebuild an existing version
- Or delete the release tag first if you need to rebuild

**"Version X.Y.Z with same hash is already in ghost.bu, skipping PR creation"**
- The ghost-stack PR already has the correct version and hash
- No action needed - the update is already in place

### Ghost-Stack PR Not Created

**"Version X.Y.Z is already in ghost.bu, skipping PR creation"**
- Before the hash comparison fix (PR #36), this happened even when hashes differed
- After the fix, this only appears when both version AND hash match
- If you see this incorrectly, ensure PR #36 is merged

**"Resource not accessible by integration"**
- The GitHub App isn't installed on ghost-stack
- Go to https://github.com/settings/apps/alloy-sysext-automation/installations
- Ensure ghost-stack is listed

### Hash Mismatch in ghost-stack

If Ignition fails with hash verification error:
1. Get the actual hash from R2:
   ```bash
   curl -s https://ghost-sysext-images.separationofconcerns.dev/alloy-X.Y.Z-amd64.raw.sha256
   ```
2. Compare with hash in ghost.bu
3. If different, the automated PR may have failed - create a manual PR with the correct hash

### Signature Verification Failed on Instance

**"Signature verification failed"**
- Public key on instance doesn't match signing key
- Check `/etc/sysupdate.alloy.d/alloy.gpg` on the instance
- Compare with the key used to sign (may need key rotation)

**To manually verify a signature:**
```bash
# On your local machine with the public key
curl -sO https://ghost-sysext-images.separationofconcerns.dev/alloy-X.Y.Z-amd64.raw
curl -sO https://ghost-sysext-images.separationofconcerns.dev/alloy-X.Y.Z-amd64.raw.asc
gpg --verify alloy-X.Y.Z-amd64.raw.asc alloy-X.Y.Z-amd64.raw
```

## Manual Operations

### Triggering a Build Manually

```bash
# For a new version
gh workflow run build-and-publish.yml --repo noahwhite/alloy-sysext-build \
  -f version=1.14.0

# Check workflow status
gh run list --repo noahwhite/alloy-sysext-build --limit 5
```

### Deleting R2 Artifacts (to force rebuild)

```bash
# Set credentials from Bitwarden
export AWS_ACCESS_KEY_ID=<r2-access-key>
export AWS_SECRET_ACCESS_KEY=<r2-secret-key>

# Delete specific version
aws s3 rm s3://<bucket>/alloy-1.13.0-amd64.raw --endpoint-url https://<account>.r2.cloudflarestorage.com
aws s3 rm s3://<bucket>/alloy-1.13.0-amd64.raw.sha256 --endpoint-url https://<account>.r2.cloudflarestorage.com
aws s3 rm s3://<bucket>/alloy-1.13.0-amd64.raw.asc --endpoint-url https://<account>.r2.cloudflarestorage.com
# Also delete the non-amd64 variants if present

# Delete release tag (so build workflow will recreate it)
gh release delete v1.13.0 --repo noahwhite/alloy-sysext-build --yes
```

### Checking Current State

```bash
# Latest release in this repo
gh release view --repo noahwhite/alloy-sysext-build

# Latest Alloy release upstream
gh release view --repo grafana/alloy

# Files in R2 (requires credentials)
aws s3 ls s3://<bucket>/ --endpoint-url https://<account>.r2.cloudflarestorage.com | grep alloy
```

## Related Repository

- **ghost-stack**: Consumes the sysext images in Flatcar Butane configuration
  - Public key deployed to `/etc/systemd/alloy-sysext.gpg.pub`
  - Merged keyring at `/etc/systemd/import-pubring.gpg` (includes vendor keys)
  - Sysupdate config at `/etc/sysupdate.alloy.d/alloy.conf` with `Verify=true`
  - Initial version pinned in `ghost.bu`
  - Auto-updates via systemd-sysupdate using SHA256SUMS manifest
