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
IP/CIDR: 203.0.113.10/32
Gateway: 198.51.100.254
Primary DNS: 8.8.8.8
Secondary DNS: 1.1.1.1
On-link: yes
```

## `chk-cve-2026nov.sh`

Read-only check for the November 2026 PHP, nginx, and Apache vulnerabilities, on the host and inside running Docker containers.

Run it as root:

```bash
sudo bash ./chk-cve-2026nov.sh
```

Or run a pinned revision directly:

```bash
curl -fsSL https://raw.githubusercontent.com/kopernix/server-utils/<COMMIT>/scripts/chk-cve-2026nov.sh | sudo bash
```

The script compares installed PHP, nginx, and Apache versions against the fixed upstream releases. When a version is older, it looks for the CVE identifiers in the Debian package changelog to detect distribution backports. It also reports services still running with replaced binaries or modules, and whether Apache has HTTP/2 enabled.

For PHP, it verifies the `session.upload_progress.enabled = Off` mitigation for every web SAPI. On Debian and Ubuntu it reads `php.ini`, `conf.d`, PHP-FPM pool overrides, and Apache `php_admin_flag` overrides. On official `php` images and other layouts it queries the PHP binary. It does not check `.htaccess` or `.user.ini` files, and it does not detect configuration changes that have not been reloaded.

Each running container is inspected through `docker exec` with `sh`. Containers without a shell are reported for manual review.

The script ends with an `OK`, `review`, or `vulnerable` summary and exits with a non-zero status when a vulnerable component is found. The CVE lists reflect the state on 20 November 2026; verify them against the official advisories. Set `NO_COLOR=1` to disable colors.

The script modifies nothing.

## Planned

- `docker-cleanup.sh`: Clean selected Docker data according to a procedure that will be provided later.
