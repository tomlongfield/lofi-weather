#!/usr/bin/env bash

# Helper logging function for systemd journal compatibility
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "Starting weather check..."

# Load secure credentials
CONFIG_FILE="/etc/weather-alert.conf"
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
else
    echo "[ERROR] Config file missing: $CONFIG_FILE" >&2
    exit 1
fi

# Configuration
LOCATIONS=("Inverness" "Cannich" "Morvich")
STATE_FILE="/var/tmp/weather_alert.hash"
FULL_ALERT=""
API_FAILED_COUNT=0

for LOC in "${LOCATIONS[@]}"; do
    log "Fetching 3-day forecast for ${LOC}..."
    JSON=$(curl -s --max-time 10 "https://wttr.in/${LOC}?format=j1" || true)

    # Validate JSON payload
    if ! echo "$JSON" | jq -e . >/dev/null 2>&1; then
        log "[WARN] Unable to parse valid JSON for ${LOC} (API down or rate-limited). Skipping location."
        ((API_FAILED_COUNT++))
        continue
    fi

    # Iterate through all 3 available forecast days
    for DAY_IDX in 0 1 2; do
        DATE_STR=$(echo "$JSON" | jq -r --argjson idx "$DAY_IDX" '(.weather[$idx].date // "") | strptime("%Y-%m-%d") | strftime("%a %d %b")' 2>/dev/null)
        if [ -z "$DATE_STR" ]; then
            continue
        fi

        MAX_WIND=$(echo "$JSON" | jq -r --argjson idx "$DAY_IDX" '(.weather[$idx].hourly | max_by(.windspeedMiles | tonumber).windspeedMiles | tonumber | floor) // 0')
        MIN_TEMP=$(echo "$JSON" | jq -r --argjson idx "$DAY_IDX" '(.weather[$idx].mintempC | tonumber | floor) // 99')

        PEAK_WIND_DATA=$(echo "$JSON" | jq -r --argjson idx "$DAY_IDX" '
            .weather[$idx].hourly | max_by(.windspeedMiles | tonumber) |
            "\(.windspeedMiles)mph@\(("0" + (.time|tonumber/100|tostring))[-2:]):00"
        ')

        HAZARD=$(echo "$JSON" | jq -r --argjson idx "$DAY_IDX" '.weather[$idx].hourly[].weatherDesc[0].value' | grep -iE 'snow|thunder|blizzard|sleet' | head -1 || true)

        DAY_ALERT=""

        if [ "$MAX_WIND" -gt 25 ]; then
            DAY_ALERT+="Wind:${PEAK_WIND_DATA} "
        fi

        if [ "$MIN_TEMP" -lt 5 ]; then
            DAY_ALERT+="Low:${MIN_TEMP}C "
        fi

        if [ -n "$HAZARD" ]; then
            SHORT_HAZ=$(echo "$HAZARD" | sed -E 's/Thundery outbreaks possible/Thunder/g; s/Patchy light snow/Light snow/g')
            DAY_ALERT+="Risk:${SHORT_HAZ} "
        fi

        if [ -n "$DAY_ALERT" ]; then
            SHORT_NAME=$(echo "$LOC" | cut -c1-3 | tr '[:lower:]' '[:upper:]')
            FULL_ALERT+="${SHORT_NAME} (${DATE_STR}): ${DAY_ALERT}\n"
            log "  -> Breach on ${DATE_STR} [${SHORT_NAME}]: ${DAY_ALERT}"
        fi
    done
done

# Guard clause: If all API requests fail, preserve state and abort run
if [ "$API_FAILED_COUNT" -eq "${#LOCATIONS[@]}" ]; then
    log "[ERROR] API calls failed for all locations. Retrying next run without modifying state."
    exit 1
fi

# State Persistence & SMS Dispatch
if [ -n "$FULL_ALERT" ]; then
    CURRENT_HASH=$(printf "%b" "$FULL_ALERT" | md5sum | awk '{print $1}')
    LAST_HASH=$(cat "$STATE_FILE" 2>/dev/null || true)

    PREV_HASH="${LAST_HASH:0:8}"
    log "Threshold breaches detected. Current Hash: ${CURRENT_HASH:0:8} | Previous Hash: ${PREV_HASH:-None}"

    if [ "$CURRENT_HASH" != "$LAST_HASH" ]; then
        log "Forecast state changed. Attempting Twilio SMS dispatch..."
        SMS_BODY=$(printf "Weather Alert:\n%b" "$FULL_ALERT")

        RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "https://api.twilio.com/2010-04-01/Accounts/${TWILIO_SID}/Messages.json" \
            --data-urlencode "Body=${SMS_BODY}" \
            --data-urlencode "From=${FROM_PHONE}" \
            --data-urlencode "To=${TO_PHONE}" \
            -u "${TWILIO_SID}:${TWILIO_TOKEN}")

        HTTP_STATUS=$(echo "$RESPONSE" | tail -n1)

        if [ "$HTTP_STATUS" -eq 201 ]; then
            log "SMS successfully sent via Twilio (HTTP 201)."
            echo "$CURRENT_HASH" > "$STATE_FILE"
        else
            log "[ERROR] Twilio API failed with HTTP status ${HTTP_STATUS}."
        fi
    else
        log "Forecast unchanged since last dispatch. SMS suppressed."
    fi
else
    log "All 3-day forecasts clear for all locations."
    
    # Only clear state if ALL location checks succeeded cleanly
    if [ "$API_FAILED_COUNT" -eq 0 ]; then
        if [ -f "$STATE_FILE" ]; then
            log "Weather cleared. Removing state file."
            rm -f "$STATE_FILE"
        fi
    else
        log "[WARN] Clear forecast observed, but skipped state clearing due to partial API failures."
    fi
fi

log "Execution complete."
