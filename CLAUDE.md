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
  build-and-publish.yml   # CI/CD pipeline
scripts/
  fetch-secrets.sh        # Retrieves R2 credentials from Bitwarden
Dockerfile                # Build container image
build-alloy-sysext.sh     # Main build script
```

## CI/CD Workflow

The `build-and-publish.yml` workflow:
1. Builds a Docker container with build tools
2. Runs `build-alloy-sysext.sh` to create the sysext image
3. Validates the image structure
4. Retrieves R2 credentials from Bitwarden via `fetch-secrets.sh`
5. Uploads to Cloudflare R2 bucket

Triggered by:
- GitHub release (extracts version from tag)
- Manual workflow dispatch (specify version)

## Secrets Management

- **BWS_ACCESS_TOKEN**: Repository secret for Bitwarden Secrets Manager access
- R2 credentials are retrieved at runtime from Bitwarden (not stored in GitHub)

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
