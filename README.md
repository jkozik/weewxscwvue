# weewxscwvue

[WeeWX](https://weewx.com/) for a Davis **Vantage Vue** weather station in
Sanibel/Captiva, Florida, served at
[weewx.sancapweather.com](https://weewx.sancapweather.com/).

```
Vantage Vue ISS ──radio, ch 1──▶ Davis Envoy ──▶ WiFiLogger (TCP) ──▶ home router
   (Florida)                                                        NAT port forward
                                                                          │ internet
                                                                          ▼
                                  Ubuntu VM (Naperville): Docker Compose
                                  ┌─────────────────────────────────────────┐
                                  │ weewx-scw   felddy/weewx 5.5, Vantage   │
                                  │             driver (type = ethernet)    │
                                  │      │ data/archive/weewx.sdb (SQLite)  │
                                  │      ▼ data/public_html (Seasons skin)  │
                                  │ nginx-scw   :8090 ──▶ Cloudflare Tunnel │
                                  │      ▼ data/divumwx (DivumWX)           │
                                  │ nginx-divumwx-scw :8091 ──▶ Cloudflare  │
                                  │      ▼ data/saratoga_html ──FTP──┐      │
                                  └──────────────────────────────────┼──────┘
                       ftp-sancapvueweewx (k8s on .208:30521) ◀──────┘
                         ──▶ NFS 192.168.100.153:/home/nfs/weather-stations/
                             sancapvueweewx/public_html ──▶ new.sancapweather.com
```
(The :8091 line is sancapweather.net, the DivumWX dashboard.)

- weewx polls the Envoy over the internet through the WiFiLogger. It reads
  live readings every few seconds and the Envoy's 5-minute archive records
  (15 minutes until 2026-11-24; see NOTES).
- The stock **Seasons** skin is served by nginx on host port **8090**. A
  Cloudflare Tunnel maps `weewx.sancapweather.com` to that port; no router
  port forwards are needed.
- The history from **2025-06-30** comes from the station's previous
  software, Cumulus. `cumulus-import/` has the scripts used for the
  import.
- Live readings are also published over **MQTT** (`weather/scw/loop`, JSON,
  every 10 s) to the `mosquitto-scw` broker. The Florida broker on osprey
  bridges them over Tailscale for Home Assistant.
- **Saratoga feed:** the [weewx-saratoga](https://github.com/ktrue/weewx-saratoga)
  extension and three extra skins write `clientraw*.txt`, `WEEWXtags.php`,
  `gauge-data.txt`, graphs and NOAA reports to **`data/saratoga_html/`**
  (not `public_html`). The weewx FTP report uploads only that folder to the
  `ftp-sancapvueweewx` server, for a Saratoga-templates site
  (new.sancapweather.com, built separately). Same setup as weewxrtlsdr →
  napervilleweather.com. The current sancapweather.com (Cumulus on the
  22222 Envoy, `sancap/` folder) is separate and untouched.
- **DivumWX dashboard:** [sancapweather.net](https://sancapweather.net/)
  (title "SanCapWeather.net") is the [DivumWX](https://github.com/Millardiang/weewx-divumwx)
  2.2.1 skin, served by `nginx-divumwx-scw` on host port **8091** through
  Cloudflare. Same version and setup as weewxrtlsdr's
  new.napervilleweather.net. See "The DivumWX dashboard" below.
- The Vue has no solar or UV sensors.

`NOTES.md` is the log of how this was built and what went wrong along the way.

**Naming:** the repo and folder are `weewxscwvue` (two Sanibel stations: an
Ambient WS2000 and this Davis Vantage Vue; Vue things get "vue" in the
name). It was `weewxscw` until 2026-11-23, and these deliberately keep the
old name: the Compose project, image and containers (`weewxscw`,
`weewxscw-weewx`, `weewx-scw`, `nginx-scw`, `mosquitto-scw`), the Zabbix
item keys (`weewxscw.*`), the backup script and tarballs (`weewxscwbck.sh`,
`/backup/weewxscw.*`), `~/secrets/weewxscw-mqtt.txt` and the MQTT topic
`weather/scw/loop`.

## Repository layout

| Path | What |
|---|---|
| `Dockerfile` | `felddy/weewx:5.5.6`, system time zone America/New_York |
| `docker-compose.yml` | `weewx-scw`, `nginx-scw` and `mosquitto-scw`, with health checks, log caps and resource limits |
| `mosquitto/` | broker config, tracked `acl`, and `setup.sh`, which installs the private acl/passwd copies |
| `data/weewx.conf.example` | weewx config template (tracked). Copy it to `data/weewx.conf`, which is git-ignored |
| `data/skins/`, `data/bin/` | stock skins and weewx's user directory, as created by `weectl station create` |
| `data/bin/user/{rtcr,ws*,stackedwindrose}.py`, `data/skins/{WEEWXtags,Clientraw,SteelSeriesGauge}` | weewx-saratoga 0.1.11 and the SteelSeries gauge template, copied from weewxrtlsdr (no installer run). `stackedwindrose.py` has a LOCAL CHANGE for WeeWX 5.5 (`stop_event`) |
| `data/skins/SaratogaNOAA` | local skin: only the NOAA monthly/yearly reports (stock Seasons templates) for the Saratoga site |
| `data/bin/user/divumwx*.py`, `stats.py`, `lastrain.py`, `time_since.py`, `data/skins/DivumWX` | DivumWX 2.2.1 code and skin, copied from weewxrtlsdr (identical to the official 2.2.0 + 2.2.1 update; no installer run). `skins/DivumWX/jsondata/archive.json.tmpl` has a LOCAL CHANGE (dashboard title) |
| `divumwx-assets/fetch.sh` | one-shot download of DivumWX's static web files (pinned version + SHA-256) into `data/divumwx`, run by the `divumwx-assets` service |
| `tools/add_divumwx.py` | adds the DivumWX settings to a weewx.conf (how the live config and the example were made) |
| `data/LICENSE.divumwx` | DivumWX's GPL-3 license |
| `weewxscwbck.sh` | weekly backup (cron) |
| `zabbix/` | Zabbix agent UserParameters and scripts (site freshness, archive age, outdoor data, reception, container health, backup age) |
| `cumulus-import/` | one-off Cumulus history import: cleanup, import config, verification |

## Secrets

`data/weewx.conf` holds the station's DDNS host name and port, the MQTT
password, the FTP password (`[StdReport] [[FTP]]`) and, if set, the
OpenWeatherMap key for DivumWX alerts (`[WeatherAPI] [[Alerts]] app_id`). It is git-ignored. `data/weewx.conf.example` is the
same file with `replace_me` placeholders. When you change the config, copy
non-secret changes into the example as well.

## Install

Requirements: Docker with the compose plugin, and Tailscale (for the MQTT
bridge to Florida). You also need a WiFiLogger (or another Davis TCP
logger) reachable at `host:port`.

The scripts assume the repo lives at **`/home/jkozik/projects/weewxscwvue`**
(`weewxscwbck.sh`, `zabbix/scripts/weewxscw_archive.py`, and the cron line).
Clone it there, or edit those paths.

1. Clone and create the live config:
   ```bash
   mkdir -p ~/projects && cd ~/projects
   git clone https://github.com/jkozik/weewxscwvue.git && cd weewxscwvue
   cp data/weewx.conf.example data/weewx.conf
   # edit data/weewx.conf, section [Vantage]:
   #   host = <ddns name or IP>     tcp_port = <port>
   # and [StdReport] [[FTP]] password = <ftp-sancapvueweewx password>
   ```
   Set `[Station]` (location, latitude, longitude, altitude) if this is a
   different station.

2. Create the web folder owned by the container's weewx user (uid 1000).
   If Docker creates it first for nginx's mount, it is owned by root, and
   weewx can't write the pages:
   ```bash
   mkdir -p data/public_html data/saratoga_html data/archive
   sudo chown 1000:1000 data/public_html data/saratoga_html data/archive   # skip if you are uid 1000
   ```

3. Check that the Envoy listens on the same channel as the outdoor unit
   (Vue default: channel 1). Run this with no other client connected:
   ```bash
   docker compose build
   docker run --rm --entrypoint weectl -v "$PWD/data:/data" weewxscw-weewx \
     device --config /data/weewx.conf --info | sed -n '/TRANSMITTERS/,/CRC/p'
   ```
   Channel 1 should be `active ... iss`, and `Total packets received` should
   be above 0. To change channels, see "Envoy channel" in `NOTES.md`.

4. MQTT broker logins. Create `~/secrets/weewxscw-mqtt.txt` (chmod 600)
   with one `user password` line each for `weewx` and `osprey-bridge`. Put
   the `weewx` password in `[StdRESTful] [[MQTT]] server_url` in
   `data/weewx.conf`. Then install the broker's private files:
   ```bash
   mosquitto/setup.sh
   ```
   weewx-mqtt (the weewx add-on in `data/bin/user/mqtt.py`) needs
   **paho-mqtt 1.6.1**; the Dockerfile pins it.

5. Tailscale, so osprey's broker can reach this one:
   ```bash
   # Ubuntu 24.04 "noble" (use your release's codename)
   curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/noble.noarmor.gpg | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
   curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/noble.tailscale-keyring.list | sudo tee /etc/apt/sources.list.d/tailscale.list
   sudo apt-get update && sudo apt-get install -y tailscale
   sudo tailscale up --hostname=weewx174 --accept-dns=false   # never --accept-routes
   tailscale ip -4      # this VM's 100.x address, used by osprey's bridge
   ```
   In the Tailscale admin console, **disable key expiry** for this machine.

6. FTP destination for the Saratoga feed: the `ftp-sancapvueweewx` server
   must be running on the Kubernetes cluster (repo
   [ftp-weather](https://github.com/jkozik/ftp-weather) on 192.168.100.208:
   `kubectl apply -f ftp-sancapvueweewx-svc-dep.yaml`, password key
   `sancapvueweewx-password` in `ftp-secrets.yaml`). Test it from this VM:
   ```bash
   echo test > /tmp/t.txt && curl -T /tmp/t.txt "ftp://sancapvueweewx:<password>@192.168.100.208:30521/t.txt"
   ```
   Without it weewx still runs; only the FTP step logs errors.

7. Start:
   ```bash
   docker compose up -d
   ```
   On first start, weewx downloads the Envoy's stored archive before it
   starts the live loop. **Don't restart it during that download.**
   Before weewx starts, the one-shot `divumwx-assets` container downloads
   DivumWX's web files into `data/divumwx` (needs internet once; check with
   `docker logs divumwx-assets-scw`).

8. Point things at this machine:
   - **Cloudflare Tunnel:** `weewx.sancapweather.com` → `<this VM's LAN IP>:8090`,
     `sancapweather.net` → `<this VM's LAN IP>:8091`.
   - **osprey's Mosquitto bridge:** `address <this VM's tailscale ip -4>:1884`,
     login `osprey-bridge`.
   - Or just a browser at `http://<host>:8090/`.

9. Optional: install the weekly backup in root's crontab (Sunday 23:45):
   ```
   45 23 * * 0 /home/jkozik/projects/weewxscwvue/weewxscwbck.sh >> /home/jkozik/projects/weewxscwvue/weewxscwbck.log 2>&1
   ```
   The script takes an online SQLite snapshot (weewx keeps running), writes
   a tarball to `/backup/weewxscw.YYYYMMDD.HH.tar.gz`, FTPs a copy (login
   from `~/.ncftp-backup.cfg`), and keeps 84 days of tarballs. The tarball
   holds `weewxscwBck/project/` (the whole repo folder, including the live
   `data/weewx.conf` and the broker's private files, but not the database),
   `weewxscwBck/db/weewx.sdb`, `weewxscwBck/db/weewxwd.sdb` (weewx-saratoga) and `weewxscwBck/secrets/weewxscw-mqtt.txt`.
   **It contains secrets; keep it private.**

10. Optional: Zabbix monitoring (see "Monitoring" below).

## Verify it's working

```bash
# 1. Containers healthy (weewx: Seasons page rewritten in the last 35 min AND
#    DivumWX loop.json in the last 5 min). divumwx-assets-scw shows "Exited (0)".
#    Use `docker ps -a` to see it.
docker ps --filter name=scw --format '{{.Names}}\t{{.Status}}'

# 2. Connected, clock in sync, live loop running
docker logs weewx-scw 2>&1 | grep -E "Clock error|Starting main packet loop" | tail -2

# 3. Live readings include OUTDOOR values (outTemp/outHumidity/windSpeed).
#    If only inTemp/barometer appear, the Envoy isn't hearing the outdoor unit (step 3).
docker logs --since 2m weewx-scw 2>&1 | grep '^LOOP' | tail -1 | tr ',' '\n' | grep -E 'outTemp|outHumidity|windSpeed'

# 4. A new archive record every 5 minutes, followed by a report
docker logs --since 10m weewx-scw 2>&1 | grep -E "Added record .* to database|Generated"

# 5. The page is served
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8090/    # expect 200

# 6. MQTT: a live JSON message (retained, so it appears at once), as the bridge sees it
docker run --rm --network host eclipse-mosquitto:2.1.2-alpine mosquitto_sub \
  -h "$(tailscale ip -4)" -p 1884 -u osprey-bridge -P '<password>' -t 'weather/scw/#' -v -C 1

# 7. Saratoga feed: clientraw.txt rewritten every ~15 s, FTP after each archive record
ls -l --time-style=+%T data/saratoga_html/clientraw.txt
docker logs --since 20m weewx-scw 2>&1 | grep ftpgenerator      # "Ftp'd NN files"

# 8. DivumWX: page served, report generated each archive record
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8091/    # expect 200
docker logs --since 10m weewx-scw 2>&1 | grep "report DivumWXReport"
```

## The DivumWX dashboard (sancapweather.net)

| | |
|---|---|
| Version | 2.2.1, same as weewxrtlsdr (needs WeeWX 5.4 or later) |
| Web folder | `data/divumwx/` (git-ignored): static files from `divumwx-assets`, `jsondata/` written by weewx, `skyfield-data/` downloaded by skyfield |
| Served by | `nginx-divumwx-scw`, host port **8091** → Cloudflare → sancapweather.net |
| Its own databases | `data/archive/divumwx_extras.sdb` (sunshine, VPD, air quality...); never changes `weewx.sdb`. Backed up weekly with the others |
| External data (no keys) | Open-Meteo forecast and air quality, aviationweather.gov METAR (**KFMY**, Fort Myers), EMSC earthquakes, NOAA space weather |
| Cards left out | UV, solar radiation, evapotranspiration (no sensors), pollen (Open-Meteo pollen covers Europe only), webcam (later: images are on Home Assistant on osprey) |
| Off | Weather alerts (need an OpenWeatherMap key in `[WeatherAPI] [[Alerts]] app_id` and `enabled = True`), AuroraWatch (UK only), Timelapse and Boltek services |
| Title | "SanCapWeather.net" from `[StdReport] [[DivumWXReport]] [[[Extras]]] station_title`, via a LOCAL CHANGE in `skins/DivumWX/jsondata/archive.json.tmpl`. Without it DivumWX would show `[Station] location`, which Seasons uses |

**Why no installer:** DivumWX's installer is interactive and puts its web
folder under `[StdReport] HTML_ROOT`. Here the code, skin and config were
copied from weewxrtlsdr's working install instead (they match the official
release files), and `divumwx-assets/fetch.sh` does the one thing the
installer did that isn't in git: unpack the web files.

**To upgrade DivumWX later:** change `VERSION`, the URLs and SHA-256 sums in
`divumwx-assets/fetch.sh`; replace `data/bin/user/divumwx*.py` and
`data/skins/DivumWX/` with the new release's files (re-apply the LOCAL
CHANGE); add any new config the release notes mention; back up
`data/archive/` first; then `docker compose up -d --build`. The new marker
file makes `divumwx-assets` lay the new web files over the old ones.
Ideally upgrade weewxrtlsdr at the same time so both stay on one version.


## Monitoring (Zabbix)

Install the agent side with sudo:
`cp zabbix/weewxscw.conf /etc/zabbix/zabbix_agentd.d/`,
`cp zabbix/scripts/weewxscw_* /etc/zabbix/scripts/`, then
`systemctl restart zabbix-agent`. Items are type "Zabbix agent" on host
weewx174.kozik.net:

| Item key | Interval | Trigger |
|---|---|---|
| `weewxscw.website.health` (0 ok / 1 banner / 2 stale / 3 down) | 5m | `min(...,#2)>0` (High) |
| `weewxscw.archive[age]` (minutes) | 5m | `last(...)>35` (High) |
| `weewxscw.archive[outtemp]` (1/0) | 5m | `max(...,30m)=0` (High) |
| `weewxscw.archive[rxcheck]` (%, Numeric float) | 5m | `avg(...,1h)<50` (Warning) |
| `weewxscw.container.health[weewx-scw]`, `[nginx-scw]`, `[mosquitto-scw]` (1/0) | 5m | `max(...,15m)=0` (Average) |
| `weewxscw.backup.age` (days) | 1h | `last(...)>8` (Warning) |

Value maps (host → Value mapping), display only; triggers use the raw
numbers:
- `SCW website health`: 0 OK, 1 Banner missing, 2 Stale or no timestamp,
  3 Unreachable. Used by `website.health`.
- `SCW OK/Problem`: 1 OK, 0 Problem. Used by the three `container.health`
  items and `archive[outtemp]`.
- `SCW no data`: -1 and 999 → No data. Used by `archive[age]` (units
  `min`), `archive[rxcheck]` (`%`) and `backup.age` (`days`).

## Things to know

- **The WiFiLogger accepts one TCP client.** After weewx disconnects, it can
  refuse new connections for about 5 minutes. weewx retries on its own, so
  don't restart repeatedly. Don't point other tools (WeatherLink, Cumulus,
  test scripts) at it while weewx is running.
- **WiFiLogger time zone must be Eastern.** The WiFiLogger syncs the Envoy's
  clock in its own time zone. When it was set to Central, the clock jumped
  back an hour on every disconnect. The setting only sticks after Save
  *and* a reboot.
- **Tailscale: use the 100.x addresses, never `--accept-routes` on this
  VM.** weewx174 is on the tailnet (`--accept-dns=false`). To reach osprey
  (Florida), use its **Tailscale address**: `tailscale status` lists every
  machine, and `tailscale ip -4` shows this VM's own address. **Don't**
  ping its Florida LAN address, 192.168.0.x; that only works from devices
  that accept routes, like the laptop. Never run `tailscale up
  --accept-routes` here: the Synology advertises **192.168.100.0/24, this
  VM's own LAN**, and accepting it could send local traffic (pfSense,
  Zabbix, the backup FTP server) through the tailnet. The MQTT bridge
  needs only the 100.x addresses.
- **The Saratoga site updates every 5 minutes.** FTP runs after each
  archive record, and the Envoy's archive interval is 5 minutes (stored in
  the Envoy; `record_generation = hardware`, so `archive_interval` in
  weewx.conf is ignored). The uploaded `clientraw.txt` is up to 5 minutes
  old even though weewx rewrites it locally every 15 s. To change the
  interval: `docker compose stop weewx`,
  `docker compose run --rm --no-deps weewx device --set-interval=N -y`,
  `docker compose start weewx`. This erases the Envoy's stored records, so
  do it just after an archive record has been saved.
- **weewx-saratoga's `weewxwd.sdb` starts empty** on a fresh install (it
  isn't backfilled from `weewx.sdb`). Until the first archive record after
  start, `WEEWXtags.php` and `clientrawextra.txt` fail with a `TypeError`
  in `alltime`; that clears by itself. On a restore, restore it with
  `weewx.sdb`.
- Logs go to `docker logs weewx-scw` (stdout), capped at 30 MB.

## Back out

`docker compose down`. Nothing outside this directory is touched, except
the items you installed yourself (and the Cloudflare hostnames): the `ftp-sancapvueweewx` server on the
cluster, the backup cron line, the Zabbix agent
files, Tailscale, and `~/secrets/weewxscw-mqtt.txt`. The images
`weewxscw-weewx`, `nginx:1.27-alpine` and `eclipse-mosquitto:2.1.2-alpine`
can be removed afterwards.
