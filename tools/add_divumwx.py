"""Add DivumWX 2.2.1 settings (taken from weewxrtlsdr's live weewx.conf) to a
weewxscwvue weewx.conf, with the Sanibel changes. Usage:
    python add_divumwx.py NAPERVILLE_CONF IN_CONF OUT_CONF
Secrets from Naperville (the OpenWeather app_id) are never copied."""
import copy
import sys

import configobj

nap = configobj.ConfigObj(sys.argv[1], interpolation=False, encoding='utf-8')
cfg = configobj.ConfigObj(sys.argv[2], interpolation=False, encoding='utf-8')

def dup(sec):
    return copy.deepcopy(sec.dict())

# 1. The report: own HTML_ROOT outside public_html and saratoga_html (neither
#    of which it must ever land in, since saratoga_html is FTP'd).
assert 'DivumWXReport' not in cfg['StdReport'], 'already has DivumWX'
cfg['StdReport']['DivumWXReport'] = dup(nap['StdReport']['DivumWXReport'])
assert cfg['StdReport']['DivumWXReport']['HTML_ROOT'] == '/data/divumwx'

# 2. Derived values DivumWX uses (ET left alone: the Vue has no solar sensor).
calc = cfg['StdWXCalculate']['Calculations']
for k in ('vpd', 'AirDensity', 'lightning_strike_count'):
    calc[k] = nap['StdWXCalculate']['Calculations'][k]

# 3. Its own databases.
for k in ('divumwx_extras_binding', 'boltek_binding'):
    cfg['DataBindings'][k] = dup(nap['DataBindings'][k])
for k in ('divumwx_extras_db', 'boltek_sqlite'):
    cfg['Databases'][k] = dup(nap['Databases'][k])

# 4. Services. Not added: TimelapseService (no webcam yet) and
#    BoltekLightningService (no Boltek lightning sensor).
svc = cfg['Engine']['Services']
def as_list(v):
    if isinstance(v, str):
        v = [x.strip() for x in v.split(',')]
    return [x for x in v if x]
def add(key, new):
    cur = as_list(svc.get(key, []))
    svc[key] = cur + [s for s in new if s not in cur]
add('data_services', ['user.divumwx.SkyfieldLoopData', 'user.divumwx.DataInjectService',
                      'user.divumwx.CloudCoverageOverrideService', 'user.divumwx.LiveDataService',
                      'user.divumwx.WeatherAPIService', 'user.divumwx_meteoalarm.MeteoalarmService'])
add('xtype_services', ['user.divumwx.AirDensityService', 'user.divumwx.vpdService',
                       'user.divumwx.LastNonZeroService'])
add('archive_services', ['user.divumwx.SunshineDuration', 'user.divumwx.DivumwxExtrasService'])

# 5. Top-level DivumWX sections.
for k in ('AirDensity', 'vpd', 'RadiationDays', 'Sunduration', 'LastNonZero',
          'DataInjectService', 'LiveData', 'SkyfieldLoopData', 'CloudCoverageOverride',
          'DivumWXCards', 'WeatherAPI', 'Timelapse', 'BoltekLightning'):
    assert k not in cfg, k
    cfg[k] = dup(nap[k])

# 6. Sanibel changes.
cards = cfg['DivumWXCards']
drop = {'cardSolarRadiation', 'cardUvIndex', 'cardEvapoTranspiration',   # no solar/UV sensor
        'cardWebcam',                                                     # webcam later
        'cardPollen'}                                                     # Open-Meteo pollen is Europe-only
cards['enabled_cards'] = [c for c in as_list(cards['enabled_cards']) if c not in drop]
for k in ('webcam_title', 'webcam_image', 'webcam_mode', 'webcam_count'):
    cards.pop(k, None)
api = cfg['WeatherAPI']
api['Alerts']['app_id'] = 'replace_me'      # OpenWeatherMap key; alerts off until one is set
api['Alerts']['enabled'] = False
api['Metar']['url'] = 'https://aviationweather.gov/api/data/metar?ids=KFMY&format=json'
api['AuroraWatch']['enabled'] = False       # UK aurora service, pointless in Florida
cfg['Timelapse']['site_root'] = '/data/divumwx'
cfg['BoltekLightning']['site_root'] = '/data/divumwx'

cfg.filename = sys.argv[3]
cfg.write()
print('wrote', sys.argv[3])
print('enabled_cards:', ', '.join(cards['enabled_cards']))
for k in ('data_services', 'xtype_services', 'archive_services'):
    print(k, '=', ', '.join(svc[k]))
