#!/bin/bash
# plex_update_check.sh
# Description: Checks for a new Plex Media Server update (public or Plex Pass beta) and,
# if a new version exists, waits for no active streams before restarting the Docker container.
#
# Configuration:
#   - Set PLEX_TOKEN to your Plex token (required).
#   - Set CONTAINER_NAME to your Plex container name (default: plex).
#   - Set PLEX_HOST and PLEX_PORT as needed (defaults: localhost:32400).
#   - Choose between 'public' (stable) or 'plexpass' (beta) by setting PLEX_CHANNEL.
#   - LOG_FILE defines where logs are written (default: /var/log/plex_update_check.log).
#
# Usage:
#   1. Edit variables below or export them as environment variables:
#        export PLEX_TOKEN="your_token_here"
#        export PLEX_CHANNEL="public"  # or "plexpass"
#        export CONTAINER_NAME="plex"
#        export LOG_FILE="/var/log/plex_update_check.log"
#   2. Make sure 'jq', 'curl', and 'docker' are installed.
#   3. Run manually or via cron: /path/to/plex_update_check.sh
#
# License: MIT

# ----- Configuration -----
CONTAINER_NAME="${CONTAINER_NAME:-plex}"                   # Docker container name
PLEX_TOKEN="${PLEX_TOKEN:-}"                               # Plex auth token (must be set)
PLEX_HOST="${PLEX_HOST:-localhost}"                        # Plex server host
PLEX_PORT="${PLEX_PORT:-32400}"                             # Plex server port
PLEX_CHANNEL="${PLEX_CHANNEL:-public}"                     # 'public' or 'plexpass'
LOG_FILE="${LOG_FILE:-/var/log/plex_update_check.log}"      # Log file path

# Loop settings
SLEEP_INTERVAL=300   # 300 seconds (5 minutes)
MAX_ATTEMPTS=12      # Maximum number of polling attempts (1 hour)

# ----- Logging Function -----
log_message() {
  local TIMESTAMP
  TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
  echo "${TIMESTAMP} - $1" | tee -a "$LOG_FILE"
}

# ----- Validate required vars -----
if [ -z "$PLEX_TOKEN" ]; then
  echo "Error: PLEX_TOKEN is not set. Exiting."
  exit 1
fi

# ----- Begin Script -----
log_message "Starting Plex update check (channel: $PLEX_CHANNEL)..."
echo "" | tee -a "$LOG_FILE"

# 1. Get current Plex version from local server API
current_version=$(curl -s "http://${PLEX_HOST}:${PLEX_PORT}/?X-Plex-Token=${PLEX_TOKEN}" |   grep -oP '<MediaContainer.*version="\K[^"]+')

if [ -z "$current_version" ]; then
  log_message "Error: Could not retrieve current Plex version. Exiting."
  exit 1
fi
log_message "Current Plex version: $current_version"

# 2. Query Plex downloads API for the latest version on chosen channel
latest_json=$(curl -s -k -L -A "PlexUpdateChecker/1.0" \  -H "X-Plex-Product: Plex Media Server" \  -H "X-Plex-Client-Identifier: update-checker" \  -H "X-Plex-Token: ${PLEX_TOKEN}" \  "https://plex.tv/api/downloads/1.json?channel=${PLEX_CHANNEL}")

latest_version=$(echo "$latest_json" | jq -r '.computer.Linux.version')

if [ -z "$latest_version" ] || [ "$latest_version" == "null" ]; then
  log_message "Error: Could not retrieve latest Plex version from API. Exiting."
  exit 1
fi
log_message "Latest Plex version available: $latest_version"

# 3. Compare versions; if different, check for active streams then restart
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
      sleep $SLEEP_INTERVAL
      attempt=$((attempt + 1))
      if [ "$attempt" -gt "$MAX_ATTEMPTS" ]; then
        log_message "Max attempts reached; forcing restart."
        break
      fi
    fi
  done

  log_message "Restarting container '$CONTAINER_NAME'..."
  docker restart "$CONTAINER_NAME" >> "$LOG_FILE" 2>&1
  if [ $? -eq 0 ]; then
    log_message "Container '$CONTAINER_NAME' restarted successfully."
  else
    log_message "Error: Failed to restart container '$CONTAINER_NAME'."
  fi
else
  log_message "No update needed. Plex is up-to-date."
fi

log_message "Plex update check completed."
