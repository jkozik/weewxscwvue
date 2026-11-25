#!/usr/bin/env python3
"""Age of the Sanibel webcam image on a public site, in whole minutes.

Usage: weewxscw_webcam_age.py net|new|com   (item weewxscw.webcam.age[...])
Prints the minutes since the image's Last-Modified, or 999 if the site
can't be reached or doesn't say (value map "SCW no data").

The image is made by ~/projects/ringcam on .128 every 5 min (Home Assistant
Ring camera -> ffmpeg timestamp -> FTP to .208), so a large age means that
cron job, Home Assistant, the FTP server or the site has stopped. It went
unnoticed 2026-05-23 to 2026-11-25; this check exists so that can't happen
again. A short name rather than a URL, so the agent can't be asked to fetch
anything else. Kept under the agent's 3 s Timeout.
"""
import email.utils
import sys
import time
import urllib.request

SITES = {
    "net": "https://sancapweather.net/webcam/sancap-bayou-view.jpg",
    "new": "https://new.sancapweather.com/mount/webcam/sancap-bayou-view.jpg",
    "com": "https://sancapweather.com/mount/webcam/sancap-bayou-view.jpg",
}


def main():
    url = SITES.get(sys.argv[1] if len(sys.argv) > 1 else "")
    if not url:
        return 999
    req = urllib.request.Request("%s?_=%d" % (url, time.time()), method="HEAD",
                                 headers={"User-Agent": "weewxscw-zabbix-check",
                                          "Cache-Control": "no-cache"})
    try:
        with urllib.request.urlopen(req, timeout=2.5) as r:
            lm = r.headers.get("Last-Modified")
        modified = email.utils.parsedate_to_datetime(lm).timestamp()
    except Exception:
        return 999
    return max(0, int((time.time() - modified) // 60))


print(main())
