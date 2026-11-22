# Development notes / history

A chronological log of what was built and why, including the problems hit
along the way. `README.md` explains how to install and check the station;
this file records how we got here and what we learned.

Background: the Florida house has two Davis Envoys receiving the same
Vantage Vue outdoor unit (ISS), each with its own WiFiLogger behind the
home router's NAT:

| Port | Envoy | Polled by |
|---|---|---|
| 22222 | original Envoy | Cumulus 1 on a Windows 10 VM (192.168.100.173, `C:\Cumulus`) |
| 22223 | second Envoy (from my father's station) | this project |

The goal is to replace Cumulus with weewx and retire the Windows VM.
Modeled on `weewxrtlsdr` (Naperville); nothing is shared with it or with
`weewx51`.

## 2026-11-14: connectivity check and first weewx instance

- Checked the path from the VM, read-only: the DDNS name resolves, TCP 22223
  is open, and the Envoy answers the Davis wake-up (`\n` → `\n\r`), `TEST`
  and `NVER` (firmware **3.83**).
- Checked VM resources: 2 vCPU, 7.8 GB RAM (6.1 GB available), 24 GB free.
  Plenty of room for a Seasons-only weewx.
- Generated a stock config with
  `weectl station create --driver=weewx.drivers.vantage --units=us ...`.
  Changes to `[Vantage]`: `type = ethernet`, `host`, `tcp_port`, and
  `timeout = 8` (instead of 4) because the Envoy is reached over the
  internet. Page name: "Weewx.SanCapWeather.com".
- Secrets: the live `data/weewx.conf` is git-ignored, and a tracked
  `weewx.conf.example` uses `replace_me` placeholders. This is the same
  pattern as weewxrtlsdr.
- **Problem:** the config created by `weectl` logs to syslog, and the
  container has no `/dev/log`, so every log line produced a traceback.
  **Fix:** added a `[Logging]` section with `handlers = console,`.
- First start: weewx downloaded the Envoy's archive memory (records from
  2026-08-11 on). **Mistake:** I restarted weewx in the middle of that
  download. Afterwards the WiFiLogger accepted TCP but answered nothing
  ("Unable to wake up Vantage console") for about 5 minutes. Lesson: the
  WiFiLogger allows **one client** and holds a dropped session for minutes,
  so restart rarely and never during the catch-up download.
- **Problem:** `data/public_html` was owned by root, because Docker created
  it for nginx's bind mount before weewx ran. **Fix:** `chown 1000:1000` via
  a throwaway alpine container.
- **Problem:** every archive record had indoor temperature and barometer
  readings but **no outdoor data**, with `rxCheckPercent` = 0, for three
  months. There were also no live readings at all and the WiFiLogger hung
  (fixed by a power-cycle).
- Port 22222 couldn't be used for comparison: Cumulus holds that
  WiFiLogger's only connection.

### Envoy channel

- `weectl device --info` (read-only) on 22223 showed the Envoy listening on
  **channel 3**, the setting from my father's station, with 0 packets
  received. The Vue is on channel 1, the default.
- Fix, with weewx stopped:
  ```
  weectl device --set-transmitter-type=1,0 -y    # channel 1 = ISS
  weectl device --set-transmitter-type=3,10 -y   # channel 3 = none
  ```
  Back out: `--set-transmitter-type=3,0` and `--set-transmitter-type=1,10`.
- Two minutes later: 50 packets received, 0 missed. Live readings showed
  outdoor temperature, humidity and wind, and the 12:45 EST archive record
  had outdoor data. The Seasons page appeared on :8090.
- The Envoy's clock was 1 hour slow after the power-cycle; weewx set it.
  This turned out to be a recurring problem (see 2026-11-17).
- Trimmed the database to start at 2026-11-14 12:45 EST, the first record
  with outdoor data. Earlier records had indoor readings only. Kept a
  backup (`weewx.sdb.pre-wipe-20261114`) and moved the old web pages aside.
  Deleted rows directly rather than emptying the database: an empty
  database would make weewx re-download the Envoy's whole indoor-only
  archive memory.
- Set altitude to 14 ft, the value stored in the Envoy, so it matches the
  Envoy's barometer correction.
- Cloudflare: `weewx.sancapweather.com` → VM port 8090 (set up by the user).

## 2026-11-17: Cumulus history import

- **Transfer:** the Windows VM has no sshd. In PowerShell, the user copied
  `C:\Cumulus\data` and `Cumulus.ini` to a staging folder (Cumulus keeps the
  current month's log open, so zipping the live folder can fail), zipped
  them with `Compress-Archive`, and sent the zip with Windows' built-in
  `scp` to `~/cumulus-import-scw/`. That folder is outside git, because
  `Cumulus.ini` can hold passwords. The host key fingerprint was checked.
  The host has no `unzip`, so I extracted with Python; PowerShell 5.1 zips
  may store paths with backslashes.
- **Cumulus.ini:** 10-minute log interval; °F, mph, inches and inHg; the
  standard 27-field log format with dd/mm/yy dates. It also gave the
  house's exact location, 26.4686, -82.16. Cumulus stores the longitude
  without the minus sign, so its calculated maximum solar peaked at local
  midnight.
- **Data:** 64,884 records from 2025-06-30 to 2026-11-17. Cleaner than
  Naperville's: no 158 °F "sensor lost" values and no stuck humidity.
  Problems:
  - A 43-day gap, 2026-08-17 to 09-29, during an internet outage at the
    house while we were in Naperville.
  - `Aug26log.txt` contains 132 NUL bytes from a Windows crash or power
    loss.
  - About 3% of timestamps appear twice: exact copies, the repeated hour
    when daylight saving ended, and stray out-of-order rows around Cumulus
    restarts.
  - The UV column is junk (14.2 or 0.0) and solar is always 0. The Vue has
    neither sensor, so both are left out.
- **`clean_cumulus.py`:**
  - strips NUL bytes;
  - drops exact duplicates;
  - keeps the longest strictly increasing run of timestamps, which drops the
    1,195 stray rows without losing any timestamp;
  - cuts off at 2026-11-14 12:45 EST.
- **Rain problem found by the first trial:** this Cumulus resets "rain since
  midnight" (field 27) *on* the 00:00 row. weewx's 00:00 record covers
  23:50 to 00:00, so rain in each day's last 10 minutes was lost; for
  example 0.15 in on 2026-06-07. The importer treats a drop in a cumulative
  value as a reset. Simply adding the missing amount to the 00:00 row could
  undercount the next interval. **Fix:** rewrite field 27 as one running
  total that never resets. The 23:50 to 00:00 increment comes from the rain
  counter (field 12), which added 0.34 in over 17 months.
- **Import config (`cumulus.conf`):** copied from weewxrtlsdr. In weewx
  5.5 the indoor temperature field is `cur_in_temp`; weewx 5.1 called it
  `curr_in_temp`. Wrong spellings produce only a warning and blank values.
  `UV_sensor` and `solar_sensor` are False.
- **Trial import** into a copy of the database (online snapshot), in a
  throwaway container with `TZ=America/New_York` and `data/bin` mounted
  read-only for the calc-missing step. 64,460 records in about 19 minutes,
  with no warnings.
- **Verification** (`verify_trial.py` against Cumulus's `dayfile.txt`,
  466 full days):
  - weewxscw's own records unchanged.
  - High temperature within 1 °F on 466 of 466 days.
  - Low temperature within 1 °F on 465 of 466 days. The exception,
    2026-02-16, is Cumulus's own 0.0 °F glitch.
  - Rain within 0.01 in on 466 of 466 days.
  - Gust within 2 mph on 459 of 466 days. Cumulus takes gusts every
    2 seconds; the logs hold 10-minute values.

  Left out: Cumulus's 5.87 in on 2026-09-29, which is six weeks of outage
  rain lumped into one day.
- **Live swap** (weewx down about 3 minutes):
  1. Stopped weewx and backed up the live database
     (`~/cumulus-import-scw/backup/weewx.sdb.pre-live-swap-20261117`).
  2. Copied the records logged since the snapshot, and the daily summaries
     for Nov 15 onward (built from live readings), into the trial copy.
     The first attempt failed on `archive_day__metadata`, which has no
     dateTime column; it rolled back cleanly.
  3. Swapped the trial copy in. Result: 64,749 records.
  4. Set the exact location.

  NOAA reports from 2025-06 onward generated on the first report cycle.

  Back out: stop weewx, copy the backup back, delete the NOAA files for
  2025 and for 2026-01 through 2026-10, start.

## 2026-11-17: health check, backup, Envoy clock

- Health check: the weewx container is healthy if the Seasons `index.html`
  has been rewritten in the last **35 minutes**: two 15-minute intervals
  plus 5 minutes. It was 65 minutes before the interval was known.
- Backup: `weewxscwbck.sh` is a separate script per project, like weewx51
  and weewxrtlsdr. A failure stays contained, and retiring the project means
  deleting one script and one cron line. It takes an online SQLite snapshot
  (no container stop, which would free the WiFiLogger and invite the
  lockout), writes a tarball to `/backup`, FTPs a copy to .143, and keeps
  84 days. Test run: the snapshot passed its integrity check with 64,749
  records, a 6.75 MB tarball, and an FTP copy whose size matched to the
  byte. Root cron: Sunday 23:45, which is UTC on this host.
- **Envoy clock jumping back 1 hour.** It happened on 2026-11-14 after the
  power-cycle and on 2026-11-17 during the database swap, always while
  weewx was disconnected. weewx's 4-hourly clock checks while connected were
  within 4 seconds. The VM's location doesn't matter: weewx runs on
  America/New_York. **Cause:** the WiFiLogger syncs the Envoy's clock using
  its own time zone setting, which was **Central**.
  - Changed it to Eastern in the WiFiLogger dashboard (192.168.0.107 on the
    Florida LAN). It reverted until saved **and rebooted**. The reboot itself
    caused one last jump (-3617 s), which weewx corrected.
  - Test: weewx stopped for 5 minutes, then restarted. The clock error was
    **-0.19 s**. Fixed.

## 2026-11-17: stale public site, Zabbix monitoring

- **Problem:** while building the Zabbix checks I found that
  weewx.sancapweather.com still showed "last update 11/14/26 17:15".
  The cause was the Nov 14 database trim: I *moved* `data/public_html` aside
  and created a new folder. A Docker bind mount follows the original folder
  even after it's renamed, so nginx kept serving the old snapshot for three
  days while weewx wrote fresh pages to the new folder. The nginx health
  check (HTTP 200) didn't notice.
  **Fix:** `docker compose restart nginx`. Lesson: never rename or replace a
  bind-mounted folder under a running container; empty it in place instead,
  or restart the container afterwards.
- **Zabbix:** added `zabbix/weewxscw.conf` (UserParameters) and two scripts,
  separate from weewx51's `weewx.conf` items:
  - a public-site check through Cloudflare (banner and `lastupdate` no
    older than 35 minutes; it would have caught the stale-nginx problem);
  - the newest archive record's age, whether it has an outdoor temperature,
    and its radio reception %;
  - Docker health for both containers;
  - backup age.

  Tested as jkozik, including negative tests for the stale, unreachable
  and wrong-banner cases. The zabbix user is in the `jkozik` and `docker`
  groups.
- Installed with sudo in a real terminal. (Run with the `!` prefix, the
  `sudo cp` silently didn't happen, so every item showed "unsupported item
  key".) Items and triggers were created in the Zabbix UI; the table is in
  `README.md`.
- **Live test:** stopped `nginx-scw` 13:45-14:06 EST. Cloudflare returned
  502, so the website item read 1. "SCW website stale or down" fired at
  13:55 and "SCW nginx container unhealthy" at 14:00. Both cleared at about
  14:10, after the restart. The Zabbix server displays Central time.

## 2026-11-17: planning a realtime link to Home Assistant

Goal: an M5Stack Tab5 on the kitchen table as a glanceable live weather
display (temperature, humidity, rain, rain rate, radar loop), driven by
Home Assistant on **osprey** (192.168.0.28, Florida LAN; Home Assistant
**Container** 2026.5.3, so there are no add-ons).

- Options considered:
  - A: a JSON file from weewx, read by HA through Cloudflare. Simple, but
    only updates every 15 minutes.
  - B: MQTT from weewx in Naperville to Florida, via a new broker plus
    WebSockets over the Cloudflare Tunnel or a port forward.
  - C: weewx publishing into Florida directly. Avoided, because it needs
    a port open into the Florida network.
- **Finding:** the 22223 WiFiLogger has a built-in **MQTT data export**
  ("Realtime.txt & wflexp.json", interval in seconds, with login and
  topic). The realtime path can therefore stay entirely on the Florida
  LAN: WiFiLogger → Mosquitto on osprey → HA → Tab5 (ESPHome). It needs
  no Naperville round trip and no new exposure, and keeps working during
  an internet outage. **weewxscw is unchanged** and remains the long-term
  record.
- Open risk: whether the WiFiLogger's export competes with weewx's
  single TCP session. When the export is enabled, this session checks
  weewx-scw's logs (`ip-read` errors, lockouts), and Zabbix watches
  polling.
- The Cloudflare mapping for weewx.sancapweather.com is a **Cloudflare
  Tunnel** to the Naperville LAN (192.168.100.174:8090). There are no
  pfSense port forwards.
- Decision: no SSH from Naperville into osprey. The osprey work is done
  by a **separate Claude Code session on osprey**, from a handoff brief
  (kept outside this public repo because it has LAN details). It covers
  Mosquitto on osprey (LAN only, password logins), the WiFiLogger MQTT
  export, HA MQTT sensors, and the Tab5 with ESPHome, including a radar
  proof of concept.

## 2026-11-18: WiFiLogger MQTT test, MQTT trial, Tailscale

- **WiFiLogger MQTT export (osprey session):** enabled 09:38 ET; the topic
  was changed (a trailing "/" was needed) at about 09:53. Each change needs
  a WiFiLogger save and reboot, and each reboot dropped weewx's connection
  for about 80 s (reconnected 09:41:07 and 09:54:41). The clock stayed
  correct (-1.3 s), confirming the time zone fix.
- **Finding:** the WiFiLogger's own dashboard and MQTT export **stopped at
  09:54:30**, within seconds of weewx reconnecting. Most likely, while a TCP
  client (weewx) is connected, the WiFiLogger hands the console to it and
  stops its own polling. So the WiFiLogger export and weewx exclude each
  other. Constraints: keep Cumulus on the other Envoy, and buy no more
  hardware. **Decision:** realtime data for Home Assistant will come from
  weewx instead.
- **MQTT trial** (throwaway containers, simulator driver):
  - weewx 5.5 + `weewx-mqtt` (matthewwall, v0.24 from `archive/master.zip`)
    + **`paho-mqtt==1.6.1`**. paho 2.x breaks this extension (upstream
    issue #42), and 1.6.1 installs fine on the image's Python 3.14.
  - It published JSON to `weather/scw/loop`.
  - `post_interval = 10` throttles to exactly one message every 10 s.
  - `obs_to_upload = none`, `append_units_label = false` and per-field
    `[[[inputs]]] format` give a tidy message of about 260 bytes. Remember
    to add `dateTime`.
  - Traffic is negligible: about 2.5 MB a day at 10 s.
  - Harmless warning: a `SyntaxWarning` from the extension's docstring.
- **Design:** two brokers and a bridge. weewx → `mosquitto-scw`
  (Naperville) ◀── bridge ── Mosquitto on osprey (Florida dials out) →
  Home Assistant → Tab5. Cloudflare was considered and rejected: Mosquitto
  bridges speak raw TCP, not WebSockets. Over a Cloudflare Tunnel that
  would need Cloudflare Access, a service token and a `cloudflared access
  tcp` relay on osprey. Cloudflare stays for websites only.
- **Tailscale on weewx174** (1.104.7, Tailscale's apt repo):
  `sudo tailscale up --hostname=weewx174 --accept-dns=false`. Key expiry is
  disabled for weewx174 and osprey. A direct connection to osprey takes
  about 64 ms. See "Tailscale" in README.md for the rules.

## 2026-11-18: Naperville MQTT broker and weewx-mqtt (branch `mqtt-bridge`)

- **`mosquitto-scw`** (`eclipse-mosquitto:2.1.2-alpine`; the bare `2.1.2`
  tag doesn't exist), host port **1884**, because weewxrtlsdr's broker has
  1883. Reachable from the Naperville LAN and the tailnet only. Password
  logins and an ACL: `weewx` may write `weather/scw/#`; `osprey-bridge`
  may only read it.
- Mosquitto 2.1 warns, and future versions will refuse, if the acl or
  passwd files aren't owned by the broker user with mode 600. So the
  tracked `mosquitto/acl` is copied by `mosquitto/setup.sh` into
  `mosquitto/config/` (owner 1883, mode 600, git-ignored). The script also
  builds `passwd` from `~/secrets/weewxscw-mqtt.txt`.
- Tests over the Tailscale address: anonymous connections and wrong
  passwords are refused; `weewx` publishes and `osprey-bridge` receives;
  `osprey-bridge` can't publish; `weewx` can't write outside its topic.
- **weewx-mqtt** installed with `weectl extension install` (backup:
  `weewx.conf.pre-mqtt`). The Dockerfile pins `paho-mqtt==1.6.1`. Config:
  `binding = loop`, `post_interval = 10`, `retain = true`, and only the
  needed fields, rounded (about 300 bytes). The add-on runs in its own
  thread and retries if the broker is down, so it can't stall polling.
- weewx was recreated at 14:16 ET and reconnected to the Envoy at once.
  Real data is flowing.
  `rxCheckPercent` isn't in live packets (archive only), so it doesn't
  appear.

- **osprey's bridge** (osprey session) connected at 14:57:12 ET, read-only
  as `osprey-bridge`. It appears as the Docker gateway 172.21.0.x, which is
  normal for a published port.
- WiFiLogger MQTT export set back to **Disable** (reboot ~15:13 ET). weewx
  dropped at 15:13:15 and reconnected at 15:14:35, clock -2.57 s.
- The broker health check was `nc -z`, which logged a connect/disconnect
  pair every minute and buried the bridge messages. Changed to a process
  check (`pidof mosquitto`).
- **Bridge reconnect test:** `mosquitto-scw` was recreated at 15:14:51 ET.
  weewx's publisher reconnected at 15:14:53 and osprey's bridge reconnected
  by itself at **15:15:03** (11 s).

## 2026-11-18: Zabbix value maps, migration notes

- Added the mosquitto container item and trigger, plus three host value
  maps (display only; triggers still use the raw numbers):
  - `SCW website health`: 0 OK / 1 Banner missing / 2 Stale or no
    timestamp / 3 Unreachable.
  - `SCW OK/Problem`: 1 OK / 0 Problem. Used by the container items and
    outdoor data.
  - `SCW no data`: -1 and 999 → No data. Used by archive age, reception and
    backup age.

  One map can't cover every item, because 1 means "banner missing" on the
  website item but "healthy" on the container items. Units: `min`, `%`,
  `days`. First readings: all OK, archive age 5 min, reception 85%,
  backup age 1 day.
- README install steps reviewed for a rebuild from a fresh clone: added
  the Tailscale step, the expected repo path
  (`/home/jkozik/projects/weewxscw`, hard-coded in the backup and Zabbix
  scripts), what the backup tarball contains, and the Zabbix value maps. A
  fresh-clone test passed: the compose file is valid, the example config
  parses and the MQTT add-on loads.
- `weewxscwbck.sh` now also saves `~/secrets/weewxscw-mqtt.txt`, the only
  plain-text copy of the bridge password, so a restore doesn't require
  re-keying osprey.

## 2026-11-22: Saratoga feed for new.sancapweather.com (branch `saratoga`)

Goal: the same weewx-saratoga → FTP → Saratoga templates setup that
weewxrtlsdr uses for napervilleweather.com, for a new site
new.sancapweather.com. The old sancapweather.com (Cumulus, 22222 Envoy,
`sancap/` folder, `ftp-sancap` server) stays untouched.

- **FTP server:** the ftp-weather repo on 192.168.100.208 runs one vsftpd
  deployment per station on the Kubernetes cluster, all on one NFS
  volume (`192.168.100.153:/home/nfs/weather-stations`, `subPath` per
  station). So no new NFS export was needed. Added `ftp-sancapweewx`
  (user `sancapweewx`, secret key `sancapweewx-password`, same naming as the
  others), NodePorts 30520/30521 and PASV 31500–31510 (next free block).
  Upload/list/delete tested from this VM.
- **weewx-saratoga** 0.1.11: copied the 8 Python files and the WEEWXtags,
  Clientraw and SteelSeriesGauge skins from weewxrtlsdr instead of running
  the installer, so the WeeWX 5.5 `stackedwindrose.py` fix comes along.
  `six` added to the Dockerfile (rtcr.py imports it).
- **Kept separate from weewx.sancapweather.com:** all Saratoga output goes
  to `data/saratoga_html` (`rtcr_path = ../saratoga_html` for clientraw.txt),
  and `[[FTP]] HTML_ROOT = saratoga_html`. weewxrtlsdr instead FTPs all of
  `public_html`, where WEEWXtags and Seasons write graphs with the same
  names. Because Seasons' NOAA files are no longer in the upload, a small
  local skin `SaratogaNOAA` generates just those (stock templates).
- Dry run first: new image with `--network none` on a copy of `data/`
  (`weectl report run` for the four reports). Everything generated except
  `WEEWXtags.php` and `clientrawextra.txt`: `$alltime` on the empty
  `weewxwd.sdb` gives `firstGoodStamp() = None`. One record in the copy
  fixed it, and live it fixed itself at the first archive record.
  `weewxwd.sdb` is not backfilled (weewxrtlsdr's also starts at its
  install date).
- Live 2026-11-22 00:54 EST, one restart. Backups:
  `~/cumulus-import-scw/backup/weewx.sdb.pre-saratoga-20261122`,
  `data/weewx.conf.pre-saratoga`, image `weewxscw-weewx:pre-saratoga`. First
  archive cycle 01:00 EST: all reports generated, `Ftp'd 63 files in
  0.63 seconds`, files present in `sancapweewx/public_html` on the NFS
  share, clientraw.txt rewritten every 15 s, no errors, Seasons unchanged.
- Limitation: the site's data is up to 15 minutes old (Envoy archive
  interval). Realtime later via `remote_server_url` (HTTP POST of
  clientraw.txt to the Saratoga site).
- Back out: copy `data/weewx.conf.pre-saratoga` to `data/weewx.conf`,
  `docker tag weewxscw-weewx:pre-saratoga weewxscw-weewx:latest`,
  `docker compose up -d --no-build weewx`.

## Still to do

- Watch weewxscw for a few days, then retire Cumulus and the Windows VM
  (.173). The 22222 Envoy can then be repurposed.
- osprey: Home Assistant sensors and the Tab5 (osprey project).
- The M5Stick + ENV III box (UV and solar) will publish to the osprey
  Mosquitto broker (osprey project). Later: feed it into this weewx too
  (MQTTSubscribe, like weewxrtlsdr's indoor sensor).
- Build the new.sancapweather.com Saratoga site on its own host, reading
  `sancapweewx/public_html`; then consider `remote_server_url` for realtime.
- Commit the ftp-weather changes on .208.
