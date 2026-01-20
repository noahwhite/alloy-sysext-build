  # Alloy Sysext Build

  Build systemd-sysext images for [Grafana Alloy](https://grafana.com/docs/alloy/) on Flatcar Container Linux.

  ## Overview

  This repository provides tooling to build Grafana Alloy as a systemd-sysext extension image for Flatcar Container
  Linux. The sysext images are automatically built via GitHub Actions and published to a Cloudflare R2 bucket for
  consumption by Flatcar instances.

  ### What is systemd-sysext?

  systemd-sysext allows extending the `/usr` directory of immutable OS images like Flatcar Container Linux with
  additional files. This enables adding software without modifying the base OS image.

  ## Usage

  ### Download Pre-built Images

  Pre-built sysext images are available at:
  https://ghost-sysext-images.separationofconcerns.dev/alloy-{VERSION}-amd64.raw
  https://ghost-sysext-images.separationofconcerns.dev/alloy-{VERSION}-amd64.raw.sha256

  Example in Butane configuration:
  ```yaml
  storage:
    files:
      - path: /opt/extensions/alloy/alloy-1.10.2-amd64.raw
        mode: 0644
        contents:
          source: https://ghost-sysext-images.separationofconcerns.dev/alloy-1.10.2-amd64.raw
          verification:
            hash: sha256-feb76c5aa5408c267d59508bd39d322c20d6fce44abd686296f4d0ca87e42671
    links:
      - target: /opt/extensions/alloy/alloy-1.10.2-amd64.raw
        path: /etc/extensions/alloy.raw
        hard: false

  Build Locally

  # Build the sysext image
  ./build-alloy-sysext.sh <VERSION>

  # Example
  ./build-alloy-sysext.sh 1.10.2

  The script will:
  1. Pull the official Grafana Alloy binary for the specified version
  2. Create a systemd-sysext directory structure
  3. Package it as a raw disk image
  4. Generate a SHA256 checksum

  Automated Builds

  GitHub Actions automatically builds new sysext images when:
  - A new release is created in this repository
  - The workflow is manually triggered with a version parameter

  Built images are automatically uploaded to the Cloudflare R2 bucket.

  Repository Structure

  .
  ├── Dockerfile              # Container image for building sysext images
  ├── build-alloy-sysext.sh   # Build script
  ├── README.md               # This file
  └── .github/
      └── workflows/
          └── build-and-publish.yml  # CI/CD pipeline

  Requirements

  - Docker (for containerized builds)
  - Bash
  - Standard Unix tools (tar, sha256sum, etc.)

  How It Works

  The build process:

  1. Downloads the specified Grafana Alloy release binary from GitHub
  2. Creates a systemd-sysext directory structure with:
    - /usr/bin/alloy - The Alloy binary
    - Extension metadata (name, version, architecture)
  3. Packages the directory as a raw ext4 filesystem image
  4. Generates SHA256 checksum for integrity verification

  The resulting .raw file can be placed in /opt/extensions/ on Flatcar and symlinked to /etc/extensions/ to extend the
  system with Alloy.

  Contributing

  Contributions are welcome! Please open an issue or pull request.

  License

  [MIT]

  Related

  - https://grafana.com/docs/alloy/
  - https://www.flatcar.org/
  - https://www.freedesktop.org/software/systemd/man/systemd-sysext.html
