#!/bin/sh
# One-shot: put DivumWX's static web files (HTML/JS/CSS/images, ~28 MB) into
# data/divumwx, so a fresh `git clone` + `docker compose up -d --build`
# recreates the sancapweather.net dashboard without committing someone
# else's files to this repo.
#
# The files come from the official release zips, pinned by version and
# SHA-256. Python code and the skin (data/bin/user/divumwx*.py,
# data/skins/DivumWX) ARE in git; only the web folder is fetched here.
# weewx itself regenerates data/divumwx/jsondata/ every archive cycle, and
# skyfield downloads data/divumwx/skyfield-data/ on first use.
#
# Runs as the `divumwx-assets` service in docker-compose.yml, before weewx.
# It does nothing (and needs no network) once the marker file for this
# version exists. To upgrade DivumWX: change the version/URLs/hashes below
# (and the Python + skin files in git), then `docker compose up -d`.
set -eu

VERSION=2.2.1
BASE_URL=https://github.com/Millardiang/weewx-divumwx/archive/refs/tags/ver.2.2.0.zip
BASE_SHA=28a55773a9a69696a836543bcb64bafd10420eed7c13838c1935cb5873540781
UPD_URL=https://github.com/Millardiang/weewx-divumwx/releases/download/ver.2.2.1/divumwx-update-2.2.0-to-2.2.1.zip
UPD_SHA=f8f2dce31e01c3b40184915e7481f4d687854b193c3cb403c3023f4b6a77e391
OWNER=${OWNER:-1000:1000}   # the weewx user in felddy/weewx

OUT=/out
MARK="$OUT/.divumwx-assets-$VERSION"

if [ -f "$MARK" ]; then
    echo "DivumWX $VERSION web files already in place"
    exit 0
fi

echo "Fetching DivumWX $VERSION web files"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
cd "$T"
wget -q -O base.zip "$BASE_URL"
wget -q -O upd.zip "$UPD_URL"
echo "$BASE_SHA  base.zip" > sums
echo "$UPD_SHA  upd.zip" >> sums
sha256sum -c sums

mkdir base upd
unzip -q base.zip -d base
unzip -q upd.zip -d upd

# Same as DivumWX's installer: copy the 2.2.0 web folder, lay the 2.2.1
# update over it, and leave out bootstrap.min.js
# (DIVUMWX_FRONTEND_EXCLUDED_FILES in install.py).
mkdir -p "$OUT"
cp -a base/weewx-divumwx-ver.2.2.0/divumwx/. "$OUT/"
cp -a upd/divumwx-update-2.2.0-to-2.2.1/divumwx/. "$OUT/"
rm -f "$OUT/js/bootstrap.min.js"

rm -f "$OUT"/.divumwx-assets-*
touch "$MARK"
chown -R "$OWNER" "$OUT"
echo "DivumWX $VERSION web files installed"
