#!/usr/bin/env python3
"""sancapweather.net (DivumWX dashboard) check through Cloudflare.

Prints one number for Zabbix (item weewxscw.divumwx.health):
  0 = healthy
  1 = wrong content (not the SanCapWeather.net dashboard)
  2 = stale: archive.json older than MAX_ARCHIVE_MIN (reports stopped) or
      loop.json older than MAX_LOOP_MIN (live readings stopped)
  3 = unreachable (HTTP error, timeout, not JSON)

Reads the two files the dashboard itself polls, through the public URL, so
it also catches Cloudflare/tunnel problems the container checks can't see.
Kept under the agent's 3 s Timeout (two 1.2 s fetches).
"""
import json
import time
import urllib.request

BASE = "https://sancapweather.net/jsondata/"
TITLE = "SanCapWeather.net"
MAX_ARCHIVE_MIN = 15   # 5-min archive interval x2 + 5
MAX_LOOP_MIN = 5       # LiveDataService rewrites loop.json every 2 s


def fetch(name):
    url = "%s%s?_=%d" % (BASE, name, time.time())
    req = urllib.request.Request(url, headers={"User-Agent": "weewxscw-zabbix-check",
                                               "Cache-Control": "no-cache"})
    with urllib.request.urlopen(req, timeout=1.2) as r:
        return json.load(r)


def main():
    try:
        archive = fetch("archive.json")
        loop = fetch("loop.json")
    except Exception:
        return 3
    try:
        meta = archive["meta"]
        if meta.get("station_location") != TITLE:
            return 1
        archive_age = (time.time() - meta["generated"] / 1000) / 60
        loop_age = (time.time() - float(loop["updated"])) / 60
    except Exception:
        return 1
    if archive_age > MAX_ARCHIVE_MIN or loop_age > MAX_LOOP_MIN:
        return 2
    return 0


print(main())
