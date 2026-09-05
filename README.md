# server-utils

Small, focused utilities for Linux server administration and maintenance.

This repository contains independent utilities intended mainly for Ubuntu and Debian. It is not a complete server administration suite.

Each script may have different requirements and consequences. Review every script and its usage instructions before running it. Some operations may be destructive.

Only bug fixes or explicitly requested changes are accepted. Automatic or AI-generated expansions are outside the scope of this repository.

Each script will include its own usage instructions when it is added.

## Download and run

Clone the repository:

```bash
git clone https://github.com/kopernix/server-utils.git
cd server-utils
```

Run the required utility:

```bash
sudo ./scripts/set-hostname.sh
sudo ./scripts/set-ubuntu-ip.sh
```

Alternatively, download an individual script:

```bash
curl -fLO https://raw.githubusercontent.com/kopernix/server-utils/main/scripts/set-hostname.sh
curl -fLO https://raw.githubusercontent.com/kopernix/server-utils/main/scripts/set-ubuntu-ip.sh
chmod 0755 set-hostname.sh set-ubuntu-ip.sh
```

Then run the downloaded script with `sudo`.

Author: Joan Puiggali aka kopernix

License: MIT
