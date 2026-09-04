#!/usr/bin/env bash
set -euo pipefail

OUTPUT_FILE="/var/www/html/weather.txt"
CACHE_DIR="/var/tmp/weather_text_cache"
mkdir -p "$(dirname "$OUTPUT_FILE")" "$CACHE_DIR"
TMP_FILE=$(mktemp "$(dirname "$OUTPUT_FILE")/.weather.XXXXXX")
trap 'rm -f "$TMP_FILE"' EXIT

LOCATIONS=("Inverness:INVERNESS" "Cannich:CANNICH" "Morvich:MORVICH")

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >&2
}

fetch_weather() {
    local location="$1"
    local title="$2"
    local cache_file="${CACHE_DIR}/${location}.txt"
    local timestamp
    timestamp=$(TZ='Europe/London' date '+%Y-%m-%d %H:%M %Z')

    log "Fetching text forecast for ${title}..."
    local JSON
    JSON=$(curl -s --max-time 10 "https://wttr.in/${location}?format=j1" || true)

    if echo "$JSON" | jq -e . >/dev/null 2>&1; then
        {
            echo "=== $title $timestamp ==="
            echo "$JSON" | jq -r '
                def clean_desc:
                    {
                        "Thundery outbreaks possible": "Thunder risk",
                        "Patchy light rain with thunder": "Lgt rain+thun",
                        "Moderate or heavy rain with thunder": "Hvy rain+thun",
                        "Patchy light snow with thunder": "Lgt snow+thun",
                        "Moderate or heavy snow with thunder": "Hvy snow+thun",
                        "Patchy freezing drizzle possible": "Fzg drizzle",
                        "Heavy freezing drizzle": "Hvy fzg dzl",
                        "Patchy light drizzle": "Light drizzle",
                        "Moderate or heavy freezing rain": "Hvy fzg rain",
                        "Light freezing rain": "Lgt fzg rain",
                        "Moderate or heavy rain shower": "Hvy rain shwr",
                        "Torrential rain shower": "Downpours",
                        "Light rain shower": "Lgt rain shwr",
                        "Moderate or heavy sleet showers": "Hvy sleet shw",
                        "Light sleet showers": "Lgt sleet shw",
                        "Moderate or heavy snow showers": "Hvy snow shwr",
                        "Light snow showers": "Lgt snow shwr",
                        "Moderate rain at times": "Occ. mod rain",
                        "Heavy rain at times": "Occ. hvy rain",
                        "Patchy light rain": "Patchy lgt rn",
                        "Patchy rain possible": "Patchy rain",
                        "Patchy light snow": "Patchy lgt sn",
                        "Patchy moderate snow": "Iso mod snow",
                        "Patchy heavy snow": "Iso hvy snow",
                        "Patchy snow possible": "Patchy snow",
                        "Moderate or heavy sleet": "Heavy sleet",
                        "Patchy sleet possible": "Patchy sleet"
                    }[.] // . | sub(" ?[Nn]earby"; "");

                .weather[] |
                "Date: \(.date | strptime("%Y-%m-%d") | strftime("%a")) \(.date)|H:\(("    " + .maxtempC)[-4:])C|L:\(("    " + .mintempC)[-4:])C",
                (.hourly[] | "\(("0" + (.time|tonumber/100|tostring))[-2:]):00|\(("    " + .tempC)[-4:])C|\(("   " + .windspeedMiles)[-3:])mph|\(("    " + .precipMM)[-4:])mm|\(.weatherDesc[0].value | clean_desc)"),
                "---"
            '
            echo ""
        } > "$cache_file"
        log "Updated cache for ${title}."
    else
        log "[WARN] Fetch failed for ${title}."
        if [ ! -f "$cache_file" ]; then
            {
                echo "=== $title [UNAVAILABLE] ==="
                echo ""
            } > "$cache_file"
        else
            log "Preserving previously cached forecast for ${title}."
        fi
    fi
}

for ENTRY in "${LOCATIONS[@]}"; do
    LOC="${ENTRY%%:*}"
    TITLE="${ENTRY##*:}"
    fetch_weather "$LOC" "$TITLE"
done

# Assemble master text output
{
    for ENTRY in "${LOCATIONS[@]}"; do
        LOC="${ENTRY%%:*}"
        cache_file="${CACHE_DIR}/${LOC}.txt"
        cat "$cache_file"
    done
} > "$TMP_FILE"

mv -f "$TMP_FILE" "$OUTPUT_FILE"
chmod 644 "$OUTPUT_FILE"
log "Successfully generated $OUTPUT_FILE."
