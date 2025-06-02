# Plex Update Checker

This repository contains a Bash script to automatically check for Plex Media Server updates (public or Plex Pass beta) and, if a new version is available, wait until there are no active streams before restarting the Docker container.

## Features

- Checks Plex version against the Plex API (stable or Plex Pass)
- Polls for active streams (default: 5-minute intervals, up to 1 hour)
- Restarts container only when safe (no active streams or forced after timeout)
- Logs activity to a configurable log file

## Prerequisites

- Docker (with Plex running as a container)
- `curl`
- `jq`
- Bash shell

## Installation

1. **Copy the script** to your server (e.g., under `/usr/local/bin` or `~/scripts`):
   ```bash
   mkdir -p ~/scripts
   cp plex_update_check.sh ~/scripts/plex_update_check.sh
   chmod +x ~/scripts/plex_update_check.sh
   ```

2. **Install dependencies** (if not already installed):
   ```bash
   # On Debian/Ubuntu-based systems:
   sudo apt update && sudo apt install -y curl jq
   ```

## Configuration

Edit the top of `plex_update_check.sh` (or set environment variables) to match your setup:

```bash
# Docker container name (default: plex)
CONTAINER_NAME="plex"

# Plex API token (required)
PLEX_TOKEN="your_plex_token_here"

# Plex server host and port (default: localhost:32400)
PLEX_HOST="localhost"
PLEX_PORT="32400"

# Which channel to track ("public" or "plexpass"; default: public)
PLEX_CHANNEL="public"

# Log file location (default: /var/log/plex_update_check.log)
LOG_FILE="/var/log/plex_update_check.log"
```

You can also override any of these by exporting environment variables before running the script.

## Usage

1. **Run manually**:
   ```bash
   /path/to/plex_update_check.sh
   ```

2. **Add to cron** (run nightly at 12:30 AM):
   ```cron
   30 0 * * * /path/to/plex_update_check.sh >> /var/log/plex_update_check.log 2>&1
   ```
   Replace `/path/to/plex_update_check.sh` with the actual path where you saved the script.

## Example Crontab Entry

```cron
# Check for updates daily at 12:30 AM, log to plex_update_check.log
30 0 * * * /home/username/scripts/plex_update_check.sh >> /var/log/plex_update_check.log 2>&1
```

## License

MIT License
