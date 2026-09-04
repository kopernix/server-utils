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
chmod 0755 scripts/set-hostname.sh
sudo ./scripts/set-hostname.sh
```

Alternatively, download only the script:

```bash
curl -fLO https://raw.githubusercontent.com/kopernix/server-utils/main/scripts/set-hostname.sh
chmod 0755 set-hostname.sh
sudo ./set-hostname.sh
```

Author: Joan Puiggali aka kopernix

License: MIT
