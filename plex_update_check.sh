#!/usr/bin/env bash
#
# plex_update_check.sh
#
# Description:
#   Checks for a new Plex Media Server update (public or Plex Pass beta).
#   If a new version exists, waits for no active streams before restarting
#   the Docker container.
#
# Usage (once you’ve cloned the repo):
#   1. Copy the example env file:  cp .env.example .env
#   2. Edit “.env” to fill in your own values (no comments—just KEY="value").
#      • PLEX_TOKEN is required if you want beta (plexpass) updates;
#        it may be empty if you only ever use “public”.
#   3. Ensure you have curl, jq, and docker installed.
#   4. Either run it manually:
#        ./plex_update_check.sh
#      or call it from cron (e.g. via `crontab -e`).
#
# .env variables (all optional except PLEX_TOKEN if using plexpass):
#   CONTAINER_NAME   → Docker container name (default: plex)
#   PLEX_CHANNEL     → “public” or “plexpass” (default: public)
#   PLEX_TOKEN       → Your Plex auth token (required for plexpass; optional for public)
#   PLEX_HOST        → Host where Plex is listening (default: localhost)
#   PLEX_PORT        → Port where Plex is listening (default: 32400)
#   LOG_FILE         → Path to log file (default: /var/log/plex_update_check.log)
#   SLEEP_INTERVAL   → How long (in seconds) to wait between stream‐checks (default: 300)
#   MAX_ATTEMPTS     → How many times to poll before forcing a restart (default: 12)
#
# Make sure the script has execute permissions:
#   chmod +x plex_update_check.sh
#
# License: MIT

# -----------------------
# 1) Load .env (if present)
# -----------------------
if [ -f "$(dirname "$0")/.env" ]; then
  # shellcheck disable=SC1090
  source "$(dirname "$0")/.env"
fi

# -----------------------
# 2) Parameter‑expansion defaults
# -----------------------
CONTAINER_NAME="${CONTAINER_NAME:-plex}"                    # Docker container name
PLEX_CHANNEL="${PLEX_CHANNEL:-public}"                      # "public" or "plexpass"
PLEX_TOKEN="${PLEX_TOKEN:-}"                                # Plex auth token (required for plexpass)
PLEX_HOST="${PLEX_HOST:-localhost}"                         # Plex server host
PLEX_PORT="${PLEX_PORT:-32400}"                              # Plex server port
LOG_FILE="${LOG_FILE:-/var/log/plex_update_check.log}"       # Log file path
SLEEP_INTERVAL="${SLEEP_INTERVAL:-300}"                      # seconds between checks
MAX_ATTEMPTS="${MAX_ATTEMPTS:-12}"                            # how many times to poll

# -----------------------
# 3) Logging helper
# -----------------------
log_message() {
  local TIMESTAMP
  TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
  echo "${TIMESTAMP} - $1" | tee -a "$LOG_FILE"
}

# -----------------------
# 4) Validate required vars
# -----------------------
if [ "$PLEX_CHANNEL" = "plexpass" ] && [ -z "$PLEX_TOKEN" ]; then
  echo "Error: PLEX_TOKEN must be set for plexpass channel; edit .env and try again."
  exit 1
fi

# -----------------------
# 5) Begin
# -----------------------
log_message "Starting Plex update check (channel: $PLEX_CHANNEL)..."
echo "" | tee -a "$LOG_FILE"

#
# 5.1 Get the current Plex version from the local API
#
current_version=$(
  curl -s "http://${PLEX_HOST}:${PLEX_PORT}/?X-Plex-Token=${PLEX_TOKEN}" \
    | grep -oP '<MediaContainer.*version="\K[^"]+'
)

if [ -z "$current_version" ]; then
  log_message "Error: Could not retrieve current Plex version. Exiting."
  exit 1
fi
log_message "Current Plex version: $current_version"

#
# 5.2 Query Plex downloads API for the latest version on the chosen channel
#
latest_json=$(
  curl -s -k -L -A "PlexUpdateChecker/1.0" \
    -H "X-Plex-Product: Plex Media Server" \
    -H "X-Plex-Client-Identifier: update-checker" \
    -H "X-Plex-Token: ${PLEX_TOKEN}" \
    "https://plex.tv/api/downloads/1.json?channel=${PLEX_CHANNEL}"
)

latest_version=$(echo "$latest_json" | jq -r '.computer.Linux.version')

if [ -z "$latest_version" ] || [ "$latest_version" = "null" ]; then
  log_message "Error: Could not retrieve latest Plex version from API. Exiting."
  exit 1
fi
log_message "Latest Plex version available: $latest_version"

#
# 5.3 Compare versions; if different, wait for no active streams before restarting
#
if [ "$latest_version" != "$current_version" ]; then
  log_message "New version detected: $latest_version. Checking for active streams..."

  attempt=1
  while true; do
    sessions=$(
      curl -s "http://${PLEX_HOST}:${PLEX_PORT}/status/sessions?X-Plex-Token=${PLEX_TOKEN}"
    )
    active_count=$(echo "$sessions" | grep -o "<Video" | wc -l)

    if [ "$active_count" -eq 0 ]; then
      log_message "No active streams. Proceeding with restart."
      break
    else
      log_message "Attempt $attempt: $active_count active stream(s) detected. Sleeping $SLEEP_INTERVAL seconds."
      sleep "$SLEEP_INTERVAL"
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