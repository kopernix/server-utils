# Utilities

## `set-hostname.sh`

Safely changes the short hostname and local FQDN after cloning a Debian or Ubuntu server.

Run it as root and follow the interactive prompts:

```bash
sudo ./set-hostname.sh
```

Before making changes, the script reports the current hostname configuration and files under `/etc` that reference it. It then shows the proposed changes and requires explicit confirmation. After applying the change, it prints the updated configuration and an `OK`, `WARN`, or `FAIL` verification summary.

The script modifies only `/etc/hostname`, the `127.0.1.1` entry in `/etc/hosts`, and the hostname managed by `hostnamectl`. It creates backups under `/var/backups/server-utils/`. It does not modify DNS, `/etc/mailname`, cloud-init, or service-specific configuration.

## Planned

- `docker-cleanup.sh`: Clean selected Docker data according to a procedure that will be provided later.
