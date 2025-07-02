# nyxta-delc

This repository contains the scripts to build a customized Alpine Linux image for a Raspberry Pi and provision it with k0s.

## Quick Start

To create a bootable Alpine image with all configurations, run the following command on a machine with an SD card reader. This will guide you through the process of downloading Alpine, partitioning the SD card, and setting up the initial system.

```bash
curl -fsSL https://nyxta.run | sh -s -- --build
```

The `nyxta.run` domain should point to the `install.sh` script in this repository.

## How it Works

The installation is a two-stage process:

### 1. Build (`build.sh`)

This script is initiated by the `--build` flag. It's designed to be run on a development machine (not the Raspberry Pi itself). It performs the following actions:

- Downloads the latest Alpine Linux image for Raspberry Pi.
- Verifies the image integrity.
- Prompts you to select a target disk (e.g., your SD card).
- Partitions and formats the disk.
- Extracts the Alpine image to the disk.
- Customizes the Alpine installation with your preferences:
    - Hostname, timezone, keymap
    - Root password and optional user creation
    - SSH authorized keys
    - Network configuration
- Sets up a first-boot service that will automatically run the `bootstrap.sh` script.

### 2. Bootstrap (`bootstrap.sh`)

This script runs automatically on the first boot of your new Alpine system on the Raspberry Pi. It handles the provisioning of the device:

- Updates the system packages.
- Installs necessary dependencies like `k0s`.
- Sets up time synchronization with `chrony`.
- Installs a single-node k0s Kubernetes cluster.
- Clones this repository to `/aether/nyxta-alpine` for future reference.

After the bootstrap process is complete, the script removes itself to prevent it from running on subsequent boots. Your device is then fully provisioned and ready to use.
