#!/bin/bash
# Weekly backup of the weewxscw project (Florida Vantage Vue via Envoy +
# WiFiLogger; weewx + nginx). Separate from ~/weewx51/weewxbck.sh and
# ~/projects/weewxrtlsdr/weewxrtlsdrbck.sh, which it is modeled on.
#
# Runs as root (writes to /backup).
# Root crontab entry (Sunday 23:45, after the weewx51 and weewxrtlsdr backups):
#   45 23 * * 0 /home/jkozik/projects/weewxscw/weewxscwbck.sh >> /home/jkozik/projects/weewxscw/weewxscwbck.log 2>&1
#
# No container shutdown needed: the SQLite database is copied with SQLite's
# online backup API, which gives a consistent snapshot while weewxd writes.
# This matters here: stopping weewx frees the WiFiLogger connection, which can
# lock weewx out for minutes and lets the Envoy clock jump (see README).
#
# FTP login (same server/user as the other backups) is read from a chmod-600
# file so the password isn't stored in this git repo. The backup itself
# includes data/weewx.conf (git-ignored; DDNS host/port).

PROJ=/home/jkozik/projects/weewxscw
BCKDIR=/backup/weewxscwBck
FTPCFG=/home/jkozik/.ncftp-backup.cfg
FTPDIR=/weewx
KEEP_DAYS=84

echo "=== weewxscw backup $(/bin/date) ==="
mkdir -p ${BCKDIR}/project ${BCKDIR}/db

# Project files; the database is snapshotted separately below
rsync -a --delete --exclude 'data/archive/' --exclude '*.log' \
  ${PROJ}/ ${BCKDIR}/project/ || { echo "rsync FAILED"; exit 1; }

# MQTT broker logins (plain text; the only copy outside the broker's hashed
# passwd). Needed to rebuild mosquitto-scw on a new VM without re-keying
# osprey's bridge. The tarball already holds data/weewx.conf (also secret).
mkdir -p ${BCKDIR}/secrets && chmod 700 ${BCKDIR}/secrets
install -m 600 /home/jkozik/secrets/weewxscw-mqtt.txt ${BCKDIR}/secrets/ \
  || echo "WARNING: ~/secrets/weewxscw-mqtt.txt not copied"

# weewxwd.sdb = WeeWX-Saratoga extra observations (created by WsArchive)
for DB in weewx.sdb weewxwd.sdb; do
  python3 - "${PROJ}/data/archive/${DB}" "${BCKDIR}/db/${DB}" <<'EOF' || { echo "db snapshot of ${DB} FAILED"; exit 1; }
import sqlite3, sys
src = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
dst = sqlite3.connect(sys.argv[2])
src.backup(dst)
ok = dst.execute("pragma integrity_check").fetchone()[0]
n = dst.execute("select count(*) from archive").fetchone()[0]
print(sys.argv[2], ok, n, "records")
dst.close(); src.close()
sys.exit(0 if ok == "ok" else 1)
EOF
done

touch /backup/weewxscwbackupage

DATE=`/bin/date +%Y%m%d`
TIME=`/bin/date +%H`
BCKUPFILE="/backup/weewxscw.$DATE.$TIME.tar.gz"
tar czf $BCKUPFILE -C /backup weewxscwBck || { echo "tar FAILED"; exit 1; }
ls -l $BCKUPFILE

ncftpput -f $FTPCFG $FTPDIR $BCKUPFILE && echo "ftp upload OK" || echo "ftp upload FAILED"

# Retention: keep ~12 weeks of local tarballs (copies also go to FTP .143).
# Only prune if today's tarball was created, so a failing backup never
# deletes the last good ones.
if [[ -s $BCKUPFILE ]]; then
 echo "pruning tarballs older than ${KEEP_DAYS} days:"
 find /backup -maxdepth 1 -name 'weewxscw.*.tar.gz' -mtime +${KEEP_DAYS} -print -delete
fi
