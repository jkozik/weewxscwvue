#!/usr/bin/env python3
"""weewxscw archive checks for Zabbix. Reads the newest archive record
(read-only, so it never blocks weewx).

Usage: weewxscw_archive.py age|outtemp|rxcheck
  age      minutes since the newest record (999 if unreadable)
  outtemp  1 if the newest record has an outdoor temperature, else 0
           (0 = Envoy not hearing the Vantage Vue outdoor unit)
  rxcheck  radio reception % of the newest record (-1 if missing)
"""
import sqlite3
import sys
import time

DB = "/home/jkozik/projects/weewxscwvue/data/archive/weewx.sdb"
what = sys.argv[1] if len(sys.argv) > 1 else "age"
fallback = {"age": 999, "outtemp": 0, "rxcheck": -1}.get(what, -1)

try:
    con = sqlite3.connect(f"file:{DB}?mode=ro", uri=True, timeout=2)
    ts, out_temp, rx = con.execute(
        "select dateTime, outTemp, rxCheckPercent from archive "
        "order by dateTime desc limit 1").fetchone()
    con.close()
except Exception:
    print(fallback)
    sys.exit(0)

if what == "age":
    print(int((time.time() - ts) // 60))
elif what == "outtemp":
    print(1 if out_temp is not None else 0)
elif what == "rxcheck":
    print(-1 if rx is None else round(rx))
else:
    print(fallback)
