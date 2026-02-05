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
version.txt                 # Tracks last built Alloy version
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

1. Reads current built version from `version.txt`
2. Checks latest stable Alloy release from GitHub API
3. Compares versions to detect updates
4. Triggers `build-and-publish.yml` if new version found
5. Updates `version.txt` and creates a tracking issue

Triggered by:
- Daily cron schedule (midnight UTC)
- Manual workflow dispatch (with optional dry-run)

## Secrets Management

| Secret | Purpose |
|--------|---------|
| `BWS_ACCESS_TOKEN` | Bitwarden Secrets Manager access |
| `GHOST_STACK_PAT` | Personal Access Token for creating PRs in ghost-stack |

R2 credentials are retrieved at runtime from Bitwarden (not stored in GitHub).

### Creating GHOST_STACK_PAT

The PAT needs permission to create branches and PRs in ghost-stack (public repository):
- `public_repo` (under `repo` scope - access public repositories only)

To create:
1. Go to https://github.com/settings/tokens
2. Generate new token (classic)
3. Under `repo` scope, select only `public_repo`
4. Set expiration to 90 days
5. Add as repository secret named `GHOST_STACK_PAT`

**Rotation:** This token expires every 90 days. See `ghost-stack/docs/token-rotation-runbook.md` for rotation procedure.

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
  alloy-{VERSION}.raw                # Compatibility symlink
  alloy-{VERSION}.raw.sha256         # Checksum
```

## Related Repository

- **ghost-stack**: Consumes the sysext images in Flatcar Butane configuration
