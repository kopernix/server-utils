# Utilities

## `set-hostname.sh`

Safely changes the short hostname and local FQDN after cloning a Debian or Ubuntu server.

Run it as root and follow the interactive prompts:

```bash
sudo ./set-hostname.sh
```

Before making changes, the script reports the current hostname configuration and files under `/etc` that reference it. It then shows the proposed changes and requires explicit confirmation. After applying the change, it prints the updated configuration and an `OK`, `WARN`, or `FAIL` verification summary.

The script modifies only `/etc/hostname`, the `127.0.1.1` entry in `/etc/hosts`, and the hostname managed by `hostnamectl`. It creates backups under `/var/backups/server-utils/`. It does not modify DNS, `/etc/mailname`, cloud-init, or service-specific configuration.

## `set-ubuntu-ip.sh`

Configures an Ubuntu Server 24.04 network interface through Netplan, using either DHCP or a static OVH Additional IP configuration.

Requirements:

- Ubuntu Server 24.04
- Netplan with `systemd-networkd`
- Root privileges

Run it from the repository:

```bash
sudo ./set-ubuntu-ip.sh
```

The script detects suitable Ethernet interfaces, backs up `/etc/netplan/50-cloud-init.yaml`, writes the selected configuration with mode `600`, and validates it with `netplan generate`. It does not use or enable Cloud-Init and does not run `netplan apply`.

When working over SSH, use the offered `netplan try` step. If the new network configuration is not confirmed, Netplan can roll back the runtime change.

Example OVH `/32` values:

```text
IP/CIDR: 51.38.162.62/32
Gateway: 51.91.70.254
Primary DNS: 8.8.8.8
Secondary DNS: 1.1.1.1
On-link: yes
```

## Planned

- `docker-cleanup.sh`: Clean selected Docker data according to a procedure that will be provided later.
