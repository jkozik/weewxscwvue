# weewxscw — Davis Vantage Vue via Davis Envoy + WiFiLogger (TCP).
# The Vantage driver is built into weewx, so nothing extra is needed; this
# Dockerfile exists so the image is pinned in one place and can grow later
# (extensions, pip packages) the same way weewxrtlsdr's does.
FROM felddy/weewx:5.5.6
USER root
# System timezone = the station's (TZ in docker-compose.yml). felddy/weewx
# leaves /etc/localtime at UTC; some skins/tools read it instead of $TZ.
RUN echo America/New_York > /etc/timezone \
    && ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime
# weewx-mqtt (publishes live data to mosquitto-scw) uses the paho-mqtt 1.x
# API; paho 2.x breaks it (upstream issue #42), so pin 1.6.1. felddy/weewx
# points PIP_TARGET/PYTHONPATH at the bind-mounted /data, which would hide a
# build-time install, so install into the venv itself (same as weewxrtlsdr).
RUN env -u PIP_TARGET -u PYTHONPATH /opt/venv/bin/pip install --no-cache-dir paho-mqtt==1.6.1
# WeeWX-Saratoga's rtcr.py (realtime clientraw.txt for new.sancapweather.com)
# still imports the Python 2/3 compat shim `six`, not present in this image's
# venv. Same PIP_TARGET/PYTHONPATH override as above (as in weewxrtlsdr).
RUN env -u PIP_TARGET -u PYTHONPATH /opt/venv/bin/pip install --no-cache-dir six
USER weewx
