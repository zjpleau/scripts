#!/bin/bash
# plex_update_check.sh
# Description: Checks for a new Plex Media Server update (public or Plex Pass beta) and,
# if a new version exists, waits for no active streams before restarting the Docker container.
#
# Configuration:
#   - Create a `.env` file (e.g., `.env.example`) and set the following variables:
#       CONTAINER_NAME="plex"
#       PLEX_CHANNEL="public"         # or "plexpass"
#       PLEX_TOKEN="YOUR_PLEX_TOKEN"
#       PLEX_HOST="localhost"
#       PLEX_PORT="32400"
#       LOG_FILE="/path/to/plex_update_check.log"
#       SLEEP_INTERVAL=300
#       MAX_ATTEMPTS=12
#
#   - Export them before running, or place them in a file named `.env` in the same directory:
#       source /path/to/.env
#
#   - Make sure `jq`, `curl`, and `docker` are installed and accessible.
#
# Usage:
#   1. Populate your `.env` file as shown above.
#   2. In this script’s directory, run:
#          source .env
#          ./plex_update_check.sh
#   3. To automate via cron, reference the full path to both the script and your `.env`:
#          0 0 * * * cd /path/to/scripts && source .env && ./plex_update_check.sh
#
# License: MIT

set -euo pipefail

# ----- Load Environment Variables -----
# If a .env file exists in this directory, source it. Otherwise, rely on exported vars.
if [ -f "$(dirname "$0")/.env" ]; then
  # shellcheck source=/dev/null
  source "$(dirname "$0")/.env"
fi

# ----- Configuration with Defaults -----
CONTAINER_NAME="${CONTAINER_NAME:-plex}"                   # Docker container name
PLEX_TOKEN="${PLEX_TOKEN:-}"                               # Plex auth token (must be set)
PLEX_HOST="${PLEX_HOST:-localhost}"                        # Plex server host
PLEX_PORT="${PLEX_PORT:-32400}"                             # Plex server port
PLEX_CHANNEL="${PLEX_CHANNEL:-public}"                     # 'public' or 'plexpass'
LOG_FILE="${LOG_FILE:-/var/log/plex_update_check.log}"      # Log file path

# Loop settings (can be overridden via .env as well)
SLEEP_INTERVAL="${SLEEP_INTERVAL:-300}"    # seconds to wait between session checks
MAX_ATTEMPTS="${MAX_ATTEMPTS:-12}"        # max retries before forcing a restart

# ----- Logging Function -----
log_message() {
  local TIMESTAMP
  TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
  echo "${TIMESTAMP} - $1" | tee -a "$LOG_FILE"
}

# ----- Validate Required Variables -----
if [ -z "$PLEX_TOKEN" ]; then
  echo "Error: PLEX_TOKEN is not set. Exiting."
  exit 1
fi

# ----- Begin Script Execution -----
log_message "Starting Plex update check (channel: $PLEX_CHANNEL)..."
echo "" | tee -a "$LOG_FILE"

# 1. Retrieve current Plex version via local API
current_version=$(curl -s "http://${PLEX_HOST}:${PLEX_PORT}/?X-Plex-Token=${PLEX_TOKEN}" \
  | grep -oP '<MediaContainer.*version="\K[^"]+')

if [ -z "$current_version" ]; then
  log_message "Error: Could not retrieve current Plex version. Exiting."
  exit 1
fi
log_message "Current Plex version: $current_version"

# 2. Query Plex downloads API for the latest version on the specified channel
latest_json=$(curl -s -k -L -A "PlexUpdateChecker/1.0" \
  -H "X-Plex-Product: Plex Media Server" \
  -H "X-Plex-Client-Identifier: update-checker" \
  -H "X-Plex-Token: ${PLEX_TOKEN}" \
  "https://plex.tv/api/downloads/1.json?channel=${PLEX_CHANNEL}")

latest_version=$(echo "$latest_json" | jq -r '.computer.Linux.version')

if [ -z "$latest_version" ] || [ "$latest_version" == "null" ]; then
  log_message "Error: Could not retrieve latest Plex version from API. Exiting."
  exit 1
fi
log_message "Latest Plex version available: $latest_version"

# 3. Compare versions; if different, check for active streams then restart container
if [ "$latest_version" != "$current_version" ]; then
  log_message "New version detected: $latest_version. Checking for active streams..."

  attempt=1
  while true; do
    sessions=$(curl -s "http://${PLEX_HOST}:${PLEX_PORT}/status/sessions?X-Plex-Token=${PLEX_TOKEN}")
    active_count=$(echo "$sessions" | grep -o "<Video" | wc -l)

    if [ "$active_count" -eq 0 ]; then
      log_message "No active streams. Proceeding with restart."
      break
    else
      log_message "Attempt $attempt: $active_count active stream(s) detected. Waiting $SLEEP_INTERVAL seconds."
      sleep "$SLEEP_INTERVAL"
      attempt=$((attempt + 1))
      if [ "$attempt" -gt "$MAX_ATTEMPTS" ]; then
        log_message "Max attempts reached; forcing restart."
        break
      fi
    fi
  done

  log_message "Restarting container '$CONTAINER_NAME'..."
  if docker restart "$CONTAINER_NAME" >> "$LOG_FILE" 2>&1; then
    log_message "Container '$CONTAINER_NAME' restarted successfully."
  else
    log_message "Error: Failed to restart container '$CONTAINER_NAME'."
  fi
else
  log_message "No update needed. Plex is up-to-date."
fi

log_message "Plex update check completed."