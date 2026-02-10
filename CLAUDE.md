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

### build-and-publish.yml

Builds, validates, publishes sysext images and creates ghost-stack PRs:

1. Builds a Docker container with build tools
2. Runs `build-alloy-sysext.sh` to create the sysext image
3. Validates the image structure
4. Retrieves R2 credentials from Bitwarden via `fetch-secrets.sh`
5. Uploads to Cloudflare R2 bucket
6. **Creates a PR in ghost-stack** to update ghost.bu with the new version and hash

Triggered by:
- GitHub release (extracts version from tag)
- Manual workflow dispatch (specify version)
- Automated trigger from check-new-releases.yml

### check-new-releases.yml

Automated version detection that runs daily:

1. Gets current built version from latest release tag in this repo
2. Checks latest stable Alloy release from GitHub API
3. Compares versions to detect updates
4. Creates a new release (which triggers build-and-publish.yml)
5. Creates a tracking issue

Triggered by:
- Daily cron schedule (midnight UTC)
- Manual workflow dispatch (with optional dry-run)

## Secrets Management

| Secret | Purpose |
|--------|---------|
| `BWS_ACCESS_TOKEN` | Bitwarden Secrets Manager access |
| `APP_ID` | GitHub App ID for alloy-sysext-automation |
| `APP_PRIVATE_KEY` | GitHub App private key (PEM format) |
| `GPG_PRIVATE_KEY` | Base64-encoded GPG private key for signing sysext images |

R2 credentials are retrieved at runtime from Bitwarden (not stored in GitHub).

### GPG Signing Key

Sysext images are signed with GPG to enable verification by systemd-sysupdate on the target systems. The signature files (`.asc`) are uploaded to R2 alongside the images.

**Key Details:**
- **Algorithm:** RSA 4096-bit (no expiration)
- **Purpose:** Sign Alloy sysext images for verification
- **Public Key Location:** Deployed to `/etc/sysupdate.alloy.d/alloy.gpg` on ghost-stack instances

### Generating the GPG Key

```bash
# Generate a new GPG key (non-interactive)
gpg --batch --gen-key <<EOF
Key-Type: RSA
Key-Length: 4096
Name-Real: Alloy Sysext Signing Key
Name-Email: alloy-sysext@separationofconcerns.dev
Expire-Date: 0
%no-protection
EOF

# List the key to get the key ID
gpg --list-secret-keys --keyid-format LONG

# Export the private key (base64-encoded for GitHub secret)
gpg --armor --export-secret-keys alloy-sysext@separationofconcerns.dev | base64 -w 0 > gpg-private-key.b64

# Export the public key (for deployment to ghost-stack)
gpg --armor --export alloy-sysext@separationofconcerns.dev > alloy-sysext-signing.pub
```

### Adding the GPG Secret

```bash
# Add to GitHub secrets (reads from the base64 file)
gh secret set GPG_PRIVATE_KEY --repo noahwhite/alloy-sysext-build < gpg-private-key.b64
```

### Deploying the Public Key

The public key must be deployed to ghost-stack instances for systemd-sysupdate to verify signatures:

1. Base64-encode the public key:
   ```bash
   base64 -w 0 alloy-sysext-signing.pub
   ```

2. Add to ghost.bu in ghost-stack (see ghost-stack CLAUDE.md for details)

### Key Rotation

**Rotation Procedure:**

1. **Generate new key pair** (follow steps above)
2. **Update GitHub secret:**
   ```bash
   gh secret set GPG_PRIVATE_KEY --repo noahwhite/alloy-sysext-build < new-gpg-private-key.b64
   ```
3. **Update ghost-stack** with the new public key
4. **Deploy ghost-stack** to push new public key to instances
5. **Re-sign existing images** (optional) or wait for next build

**Note:** During rotation, old images will fail verification until the new public key is deployed.

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

## Related Repository

- **ghost-stack**: Consumes the sysext images in Flatcar Butane configuration
