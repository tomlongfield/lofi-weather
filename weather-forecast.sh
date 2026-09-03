#!/usr/bin/env bash

# Output destination (defaults to standard web root, override via environment if needed)
OUTPUT_FILE="${OUTPUT_FILE:-/var/www/html/weather.txt}"

# Locations to forecast
LOCATIONS=("Inverness" "Cannich" "Morvich")

fetch_weather() {
  local location="$1"
  local title="$2"

  echo "=== $title ==="
  curl -s "wttr.in/${location}?format=j1" | jq -r '
    .weather[] |
    "Date: \(.date | strptime("%Y-%m-%d") | strftime("%a")) \(.date) | H: \(("   " + .maxtempC)[-3:])C | L: \(("   " + .mintempC)[-3:])C",
    (.hourly[] | " \(("0" + (.time|tonumber/100|tostring))[-2:]):00 | \(("   " + .tempC)[-3:])C | \(("   " + .windspeedMiles)[-3:])mph | \(("    " + .precipMM)[-4:])mm | \(.weatherDesc[0].value)"),
    "---"
  ' | sed -E \
      -e 's/ ?[Nn]earby//g' \
      -e 's/Patchy light rain with thunder/Lgt rain+thun/g' \
      -e 's/Moderate or heavy rain with thunder/Hvy rain+thun/g' \
      -e 's/Patchy light snow with thunder/Lgt snow+thun/g' \
      -e 's/Moderate or heavy snow with thunder/Hvy snow+thun/g' \
      -e 's/Thundery outbreaks possible/Thunder risk/g' \
      -e 's/Patchy freezing drizzle possible/Fzg drizzle/g' \
      -e 's/Heavy freezing drizzle/Hvy fzg dzl/g' \
      -e 's/Patchy light drizzle/Light drizzle/g' \
      -e 's/Moderate or heavy freezing rain/Hvy fzg rain/g' \
      -e 's/Light freezing rain/Lgt fzg rain/g' \
      -e 's/Moderate or heavy rain shower/Hvy rain shwr/g' \
      -e 's/Torrential rain shower/Downpours/g' \
      -e 's/Light rain shower/Lgt rain shwr/g' \
      -e 's/Moderate or heavy sleet showers/Hvy sleet shw/g' \
      -e 's/Light sleet showers/Lgt sleet shw/g' \
      -e 's/Moderate or heavy snow showers/Hvy snow shwr/g' \
      -e 's/Light snow showers/Lgt snow shwr/g' \
      -e 's/Moderate rain at times/Occ. mod rain/g' \
      -e 's/Heavy rain at times/Occ. hvy rain/g' \
      -e 's/Patchy light rain/Patchy lgt rn/g' \
      -e 's/Patchy rain possible/Patchy rain/g' \
      -e 's/Patchy light snow/Patchy lgt sn/g' \
      -e 's/Patchy moderate snow/Iso mod snow/g' \
      -e 's/Patchy heavy snow/Iso hvy snow/g' \
      -e 's/Patchy snow possible/Patchy snow/g' \
      -e 's/Moderate or heavy sleet/Heavy sleet/g' \
      -e 's/Patchy sleet possible/Patchy sleet/g' \
      -e 's/  *$//g'
  echo ""
}

{
  echo "Weather Forecast"
  echo "Last Updated: $(date '+%Y-%m-%d %H:%M %Z')"
  echo "=========================================="
  echo ""

  for loc in "${LOCATIONS[@]}"; do
    fetch_weather "$loc" "${loc^^}"
  done

} > "$OUTPUT_FILE"
