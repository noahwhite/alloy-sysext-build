# Grafana Alloy systemd-sysext Build Tooling

Build tooling for creating Grafana Alloy systemd-sysext images for Flatcar Container Linux.

## Purpose

This repository provides automated build tooling to package [Grafana Alloy](https://grafana.com/docs/alloy/) as a systemd-sysext image for Flatcar Container Linux. systemd-sysext allows you to extend the immutable Flatcar base system with additional binaries and services without modifying the root filesystem.

## What is systemd-sysext?

systemd-sysext (system extension) images provide a way to overlay additional files onto an immutable OS like Flatcar Container Linux. When merged, the files in the sysext image appear in the host filesystem at their defined paths (e.g., `/usr/local/bin/alloy`).

Key benefits:
- **Immutability**: Extends the system without modifying the base OS
- **Atomic operations**: Images are merged/unmerged as atomic units
- **Version management**: Easy to swap versions by changing which image is active
- **Persistence**: Survives OS updates

## Build Requirements

- Docker or Podman
- Internet connection (to download Alloy releases)

The build container includes all necessary tools:
- Ubuntu 22.04 base
- `curl`, `wget`, `unzip`
- `squashfs-tools` (for creating the image)
- `xz-utils` (for compression)

## Usage

### Build the Container Image

```bash
docker build -t alloy-sysext-builder .
```

### Run the Build

```bash
docker run --rm \
  -v "${PWD}/output:/output" \
  alloy-sysext-builder \
  /build/build-alloy-sysext.sh
```

This will:
1. Download the specified Alloy version from GitHub releases
2. Create the systemd-sysext directory structure
3. Install the Alloy binary
4. Generate a systemd service unit
5. Create extension metadata
6. Package everything into a squashfs image
7. Generate SHA256 checksums

### Customize the Build

Edit the configuration variables in `build-alloy-sysext.sh`:

```bash
VERSION="1.10.2"           # Alloy version to build
ARCHITECTURE="amd64"        # Target architecture
SYSEXT_NAME="alloy"        # Extension name
```

## Output Format

The build produces the following files in the `output/` directory:

```
alloy-1.10.2-amd64.raw          # Architecture-specific sysext image
alloy-1.10.2-amd64.raw.sha256   # SHA256 checksum
alloy-1.10.2.raw                # Compatibility version (same content)
alloy-1.10.2.raw.sha256         # SHA256 checksum
```

### File Structure

The sysext image contains:

```
/usr/local/bin/alloy                                    # Alloy binary
/usr/lib/systemd/system/alloy.service                   # systemd unit
/usr/lib/extension-release.d/extension-release.alloy    # Extension metadata
```

## Using the sysext Image on Flatcar

### 1. Copy the Image to Flatcar

```bash
scp output/alloy-1.10.2-amd64.raw core@your-flatcar-host:/var/lib/extensions/
```

### 2. Merge the Extension

```bash
systemd-sysext refresh
systemd-sysext list
```

### 3. Verify the Binary

```bash
which alloy
alloy --version
```

### 4. Configure and Enable the Service

Create your Alloy configuration:

```bash
sudo mkdir -p /var/mnt/storage/alloy
sudo vi /var/mnt/storage/alloy/config.alloy
```

Enable and start the service:

```bash
sudo systemctl daemon-reload
sudo systemctl enable alloy.service
sudo systemctl start alloy.service
sudo systemctl status alloy.service
```

### 5. View Logs

```bash
journalctl -u alloy.service -f
```

## systemd-sysext Image Format

The sysext image is a squashfs filesystem compressed with xz. It must include:

1. **Extension metadata** at `/usr/lib/extension-release.d/extension-release.<name>`:
   ```
   ID=_any
   ARCHITECTURE=x86-64
   ```
   
   - `ID=_any` makes it compatible with any OS (not just Flatcar)
   - `ARCHITECTURE` must match the host architecture

2. **File hierarchy** under standard paths:
   - `/usr/local/bin/` for binaries
   - `/usr/lib/systemd/system/` for systemd units
   - Other `/usr/` paths as needed

3. **Squashfs format** with xz compression for optimal size

## Service Configuration

The included systemd service (`alloy.service`) is configured with:

- **Config location**: `/var/mnt/storage/alloy/config.alloy`
- **State directory**: `/var/lib/alloy` (automatically created)
- **Security hardening**: NoNewPrivileges, ProtectSystem, ProtectHome, PrivateTmp
- **Automatic restart**: On failure with 10s delay

You can customize the service by editing `build-alloy-sysext.sh` before building.

## Updating Alloy

To update to a new Alloy version:

1. Update the `VERSION` variable in `build-alloy-sysext.sh`
2. Rebuild the image
3. Copy the new image to `/var/lib/extensions/` on your Flatcar host
4. Remove the old image
5. Run `systemd-sysext refresh`
6. Restart the service: `sudo systemctl restart alloy.service`

## Troubleshooting

### Extension not merging

Check extension status:
```bash
systemd-sysext status
```

Verify the image format:
```bash
unsquashfs -ll /var/lib/extensions/alloy-1.10.2-amd64.raw
```

### Service not starting

Check logs:
```bash
journalctl -u alloy.service -n 50
```

Verify binary:
```bash
file /usr/local/bin/alloy
/usr/local/bin/alloy --version
```

Check config syntax:
```bash
/usr/local/bin/alloy fmt /var/mnt/storage/alloy/config.alloy
```

## References

- [Grafana Alloy Documentation](https://grafana.com/docs/alloy/)
- [systemd-sysext Documentation](https://www.freedesktop.org/software/systemd/man/systemd-sysext.html)
- [Flatcar Container Linux Documentation](https://www.flatcar.org/docs/latest/)

## License

MIT License - see [LICENSE](LICENSE) file for details.
