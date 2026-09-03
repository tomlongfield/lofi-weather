#!/usr/bin/env bash

# Load secure credentials
if [ -f "/etc/weather-alert.conf" ]; then
  source "/etc/weather-alert.conf"
else
  echo "Config file missing!"
  exit 1
fi

# Configure your locations
LOCATIONS=("Inverness" "Cannich" "Morvich")

FULL_ALERT=""

for LOC in "${LOCATIONS[@]}"; do
  # Fetch JSON from wttr.in
  JSON=$(curl -s "wttr.in/${LOC}?format=j1")
  if [ -z "$JSON" ]; then continue; fi

  # Get tomorrow's date format (e.g. "Fri 04")
  DATE_STR=$(echo "$JSON" | jq -r '.weather[1].date | strptime("%Y-%m-%d") | strftime("%a %d")')

  # Find peak wind speed and the specific hour it hits
  PEAK_WIND_DATA=$(echo "$JSON" | jq -r '
    .weather[1].hourly | max_by(.windspeedMiles | tonumber) |
    "\(.windspeedMiles)mph@\(("0" + (.time|tonumber/100|tostring))[-2:]):00"
  ')
  MAX_WIND=$(echo "$PEAK_WIND_DATA" | cut -d'm' -f1)

  # Find lowest temperature and hazards
  MIN_TEMP=$(echo "$JSON" | jq -r '.weather[1].mintempC | tonumber')
  HAZARD=$(echo "$JSON" | jq -r '.weather[1].hourly[].weatherDesc[0].value' | grep -iE 'snow|thunder|blizzard|sleet' | head -1)

  LOC_ALERT=""

  # Threshold Checks
  if [ "$MAX_WIND" -gt 25 ]; then
    LOC_ALERT+="Wind:${PEAK_WIND_DATA} "
  fi

  if [ "$MIN_TEMP" -lt 5 ]; then
    LOC_ALERT+="Low:${MIN_TEMP}C "
  fi

  if [ -n "$HAZARD" ]; then
    # Clean up hazard string slightly for SMS brevity
    SHORT_HAZ=$(echo "$HAZARD" | sed -E 's/Thundery outbreaks possible/Thunder/g; s/Patchy light snow/Light snow/g')
    LOC_ALERT+="Risk:${SHORT_HAZ} "
  fi

  # If this location triggered any warnings, append a line
  if [ -n "$LOC_ALERT" ]; then
    # Uses 3-letter codes (INV, CAN, MOR) to save SMS space
    SHORT_NAME=$(echo "$LOC" | cut -c1-3 | tr '[:lower:]' '[:upper:]')
    FULL_ALERT+="${SHORT_NAME} (${DATE_STR}): ${LOC_ALERT}\n"
  fi
done

# Send SMS only if there are alerts
if [ -n "$FULL_ALERT" ]; then
    SMS_BODY=$(printf "Weather Alert:\n%b" "$FULL_ALERT")
    
    curl -s -X POST "https://api.twilio.com/2010-04-01/Accounts/${TWILIO_SID}/Messages.json" \
    --data-urlencode "Body=${SMS_BODY}" \
    --data-urlencode "From=${FROM_PHONE}" \
    --data-urlencode "To=${TO_PHONE}" \
    -u "${TWILIO_SID}:${TWILIO_TOKEN}" >/dev/null
fi
