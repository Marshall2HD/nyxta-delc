---
applyTo: '**'


Script Initialization:
``--build:``
```
curl -fsSL https://nyxta.run | sh -s -- --build
```
``--build`` is a gui to download alpine, and bake your overlay preferencies, into it.

The script will:
PRE CHECKS;
WAS ``--build`` passed? then start build.sh otherwise start bootstrap.sh
on the following urls = https://raw.githubusercontent.com/Marshall2HD/nyxta-delc/refs/heads/main/templates/scripts/build.sh
on the following urls = https://raw.githubusercontent.com/Marshall2HD/nyxta-delc/refs/heads/main/templates/scripts/bootstrap.sh

1. Create a temp directory for the build.
2. Clone the Repo (https://github.com/Marshall2HD/nyxta-delc.git)
3. Download the latest Alpine Linux image for Raspberry Pi. (https://dl-cdn.alpinelinux.org/alpine/v3.22/releases/armv7/alpine-rpi-3.22.0-armv7.tar.gz)
4. Download Image hash (https://dl-cdn.alpinelinux.org/alpine/v3.22/releases/armv7/alpine-rpi-3.22.0-armv7.tar.gz.sha256)
5. Verify the downloaded image against the hash.
6. List disks
7. Prompt the user to select a disk to write the image to.
8. Are you sure you want to write the image to the selected disk?
9. Format the selected disk.
10. Write the Alpine Linux image to the selected disk.
11. Mount the disk.
12. Extract the Alpine tarball into the mounted partition
13. Ensure boot directory is populated (some Pi bootloaders expect it)
14. Ask user for hostname it wants (default echo "nyxta-alpine" > /mnt/alpine/etc/hostname)
15. Ask user timezone (defaults to "echo "America/New_York" > /mnt/alpine/etc/timezone")
16. Ask user for keymap (defaults to "echo "us" > /mnt/alpine/etc/keymaps/default")
17. Ask user for root password (defaults "echo <HASHED PASSWORD HERE LOOKS NEEDS IMPLEMENTATION, IF EMPTY GIVE WARNING> > /mnt/alpine/etc/shadow")
18. Ask user if wants to create optional user (defaults to none, saves to /etc/sudoers.d/<user>)
19. Asks user for optional user name (defaults to username set in optioanl user)
20. Ask user for optional user password (defauts to none, saves to /etc/shadow)
20.5: Use mkdir -p /root/.ssh && chmod 700 before dropping the key in.
21. Ask user for authorized ssh key VALUE (saves input value to /etc/ssh/authorized_keys and /root/.ssh/authorized_keys)
21.5: Set up chrony (apk add chrony && rc-update add chronyd)
22. sets /etc/lbu/lbu.conf with USE_OVERLAY="yes"
23. sets /etc/lbu/include listing files to persist
24. sets /etc/network/interfaces with dhcp and autoconfig
25. asks user for age.key value (not file) saves it somewhere in /etc/ 
26. saves /etc/local.d/bootstrap.sh to run as sudo with the following content;
```curl -fsSL https://nyxta.run | sh```


On boot /etc/local.d/bootstrap.sh should be run grabing bootstrap.sh from the repo and running it.
The bootstrap.sh will do the following=
1. Update Alpine security stuff
2. Install K0s, Cillium, Traefik, Flux, Helm, Kustomization.
3. Download a copy of the repo at /aether/nyxta-alpine/
4. Setup cubernetes single node cluster with k0s.
5. Setup other services.