#!/bin/bash
# weewxscw public website check (modeled on weewx51's weewx_website_health.sh)
# Returns: 0=healthy, 1=banner missing, 2=timestamp stale/missing, 3=unreachable
#
# Reads the page through Cloudflare, so it catches problems the container
# health checks can't, e.g. nginx serving an old copy of public_html.

URL="https://weewx.sancapweather.com/"
BANNER="Weewx.SanCapWeather.com"
MAX_AGE_MINUTES=35          # 15-min interval x2 + 5 (was); fine for 5-min too

# Keep under the agent's 3 s default Timeout
CONTENT=$(curl -s -m 2.5 "$URL" 2>/dev/null)
if [ $? -ne 0 ] || [ -z "$CONTENT" ]; then
    echo 3; exit 0
fi

if ! echo "$CONTENT" | grep -q "$BANNER"; then
    echo 1; exit 0
fi

# <p class="lastupdate">MM/DD/YY HH:MM:SS</p>, station local time (Eastern)
TIMESTAMP=$(echo "$CONTENT" | grep -oP '(?<=<p class="lastupdate">)[^<]+' | head -1)
TS_EPOCH=$(TZ="America/New_York" date -d "$TIMESTAMP" +%s 2>/dev/null)
if [ -z "$TIMESTAMP" ] || [ -z "$TS_EPOCH" ]; then
    echo 2; exit 0
fi

AGE=$(( ($(date +%s) - TS_EPOCH) / 60 ))
if [ "$AGE" -gt "$MAX_AGE_MINUTES" ]; then
    echo 2
else
    echo 0
fi
