"""Photon-compatible proxy in front of the local photon, for Dawarich on the homeserver.

Dawarich always asks photon for lang=en and reads only properties.city / street / housenumber.
In Japan that gives "Koto" and "Bunkyo", files every Tokyo ward and Tokyo city under 東京都
(photon puts the ward in `district`, which Dawarich never reads), and turns addresses into the
nearest road name, because OSM Japan addresses by block, not by street. So for results in
Japan this asks for the local language and moves the fields to where Dawarich looks; anywhere
else the request goes through untouched, English and all.

The ward can't always come from photon: around 足立区東和 the neighbourhood sits where the
ward should (district=東和, city=東京都) and 足立区 appears nowhere in the hierarchy. So when
city is only a prefecture, the municipality comes from MLIT's 大字・町丁目レベル位置参照情報
(出典: 国土交通省) instead — the 町丁目 of the same name nearest to the feature. The 47
prefecture CSVs (a few MB in all) are fetched into ~/.local/share/photon/isj on first start.

The local photon only holds Japan, so a point abroad would come back with no name at all. Those
are answered here from GeoNames' cities1000 (every town of 1,000 people or more, about 11 MB,
fetched into ~/.local/share/photon/geonames on first start): the nearest town, its state and
its country. That is town-level only, no street, but it stays on this machine and covers every
country; a full photon index for one more country is tens of GB.

    python3 proxy.py              serve on :2323, upstream photon on 127.0.0.1:2322
    python3 proxy.py --selftest   check the Japanese rewrite against real photon output
"""

import csv
import io
import json
import math
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

UPSTREAM = "http://127.0.0.1:2322"
PREFECTURE = re.compile(r"[都道府県]$")
ISJ_DIR = Path.home() / ".local/share/photon/isj"
ISJ_URL = "https://nlftp.mlit.go.jp/isj/dls/data/19.0b/{:02d}000-19.0b.zip"  # 令和7年
NEAREST_ONLY_KM = 3  # without a name match, trust the nearest 町丁目 only this close

TOWNS = {}  # {prefecture: [(町丁目名, 市区町村名, lat, lon)]}

GEONAMES_DIR = Path.home() / ".local/share/photon/geonames"
GEONAMES_URL = "https://download.geonames.org/export/dump/"
JAPAN = (20.0, 46.0, 122.0, 154.0)  # lat min/max, lon min/max: what the local photon index covers
PLACES = {}  # {(floor(lat), floor(lon)): [(name, state, country, countrycode, lat, lon)]}


def load_towns(directory=ISJ_DIR):
    directory.mkdir(parents=True, exist_ok=True)
    for code in range(1, 48):
        path = directory / f"{code:02d}.csv"
        if path.exists():
            continue
        try:
            with urllib.request.urlopen(ISJ_URL.format(code), timeout=60) as r:
                archive = zipfile.ZipFile(io.BytesIO(r.read()))
            member = next(n for n in archive.namelist() if n.endswith(".csv"))
            path.with_suffix(".tmp").write_bytes(archive.read(member))
            path.with_suffix(".tmp").rename(path)
        except (OSError, zipfile.BadZipFile, StopIteration) as e:
            # Serve without it; the next restart tries again.
            print(f"isj {code:02d}: {e!r}", file=sys.stderr, flush=True)
        time.sleep(1)  # a government server
    towns = {}
    for path in directory.glob("*.csv"):
        with open(path, encoding="cp932", newline="") as f:
            for row in csv.DictReader(f):
                towns.setdefault(row["都道府県名"], []).append(
                    (row["大字町丁目名"], row["市区町村名"], float(row["緯度"]), float(row["経度"])))
    return towns


def km(lat1, lon1, lat2, lon2):
    return math.hypot(lat2 - lat1, (lon2 - lon1) * math.cos(math.radians(lat1))) * 111.2


def municipality(prefecture, name, lat, lon, towns):
    rows = towns.get(prefecture, [])
    named = [t for t in rows if t[0] == name]
    best = min(named or rows, key=lambda t: km(lat, lon, t[2], t[3]), default=None)
    if best and (named or km(lat, lon, best[2], best[3]) <= NEAREST_ONLY_KM):
        return best[1]
    return None


def localize(props, coords=None, towns=TOWNS):
    """Rewrite one Japanese photon feature's properties in place. coords is [lon, lat]."""
    city, district = props.get("city"), props.get("district")
    # 東京都/千代田区, 東京都/八王子市, 東京都/東和: city is only the prefecture.
    # 横浜市/西区 already has the municipality in city and stays as it is.
    if city and PREFECTURE.search(city):
        found = coords and municipality(city, props.get("locality") or district, coords[1], coords[0], towns)
        if found or district:
            props["state"] = props.get("state") or city
            props["city"] = found or district
    # A digits-only street is the 街区 number (Skytree: street "1", housenumber "2" = 1-2).
    # Anything else is just the nearest named road, which is not part of a Japanese address.
    locality = props.get("locality")
    if locality:
        street = props.get("street")
        block = street if street and street.isdigit() else None
        props["street"] = locality
        props["housenumber"] = "-".join(x for x in (block, props.get("housenumber")) if x) or None
    return props


def fetch(path, query):
    url = f"{UPSTREAM}{path}?{urllib.parse.urlencode(query, doseq=True)}"
    with urllib.request.urlopen(url, timeout=10) as r:
        return r.status, r.read()


def load_places(directory=GEONAMES_DIR):
    directory.mkdir(parents=True, exist_ok=True)

    def get(name):
        path = directory / name
        if not path.exists():
            with urllib.request.urlopen(GEONAMES_URL + name, timeout=120) as r:
                path.with_suffix(".tmp").write_bytes(r.read())
            path.with_suffix(".tmp").rename(path)
        return path

    rows = lambda name: (l.split("\t") for l in get(name).read_text(encoding="utf-8").splitlines()
                         if l and not l.startswith("#"))
    countries = {f[0]: f[4] for f in rows("countryInfo.txt")}
    states = {f[0]: f[1] for f in rows("admin1CodesASCII.txt")}
    cells = {}
    with zipfile.ZipFile(get("cities1000.zip")) as z, z.open("cities1000.txt") as fh:
        for line in io.TextIOWrapper(fh, encoding="utf-8"):
            f = line.rstrip("\n").split("\t")
            lat, lon, cc = float(f[4]), float(f[5]), f[8]
            cells.setdefault((math.floor(lat), math.floor(lon)), []).append(
                (f[2], states.get(f"{cc}.{f[10]}"), countries.get(cc, cc), cc, lat, lon))
    return cells


def in_japan(lat, lon):
    return JAPAN[0] <= lat <= JAPAN[1] and JAPAN[2] <= lon <= JAPAN[3]


def nearest_place(lat, lon, cells=PLACES):
    # ponytail: 1-degree grid without wrap at ±180 longitude; fine unless you live on the date line.
    for r in (1, 3):
        near = [p for dy in range(-r, r + 1) for dx in range(-r, r + 1)
                for p in cells.get((math.floor(lat) + dy, math.floor(lon) + dx), ())]
        if near:
            return min(near, key=lambda p: km(lat, lon, p[4], p[5]))
    return None


def place_features(lat, lon, cells=PLACES):
    """A photon-shaped answer naming the nearest GeoNames town, for points the local photon can't see."""
    p = nearest_place(lat, lon, cells)
    if not p:
        return {"type": "FeatureCollection", "features": []}
    name, state, country, cc, plat, plon = p
    props = {"type": "city", "name": name, "city": name, "state": state, "country": country, "countrycode": cc}
    return {"type": "FeatureCollection",
            "features": [{"type": "Feature", "geometry": {"type": "Point", "coordinates": [plon, plat]},
                          "properties": props}]}


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        url = urllib.parse.urlsplit(self.path)
        query = urllib.parse.parse_qs(url.query)
        try:
            lat, lon = float(query["lat"][0]), float(query["lon"][0])
        except (KeyError, ValueError):
            lat = lon = None
        try:
            if lat is not None and not in_japan(lat, lon):
                self.reply(200, json.dumps(place_features(lat, lon), ensure_ascii=False).encode())
                return
            status, body = fetch(url.path, {**query, "lang": ["default"]})
            features = json.loads(body).get("features") or []
            if features and features[0]["properties"].get("countrycode") == "JP":
                for f in features:
                    if f["properties"].get("countrycode") == "JP":
                        localize(f["properties"], (f.get("geometry") or {}).get("coordinates"))
                body = json.dumps({"type": "FeatureCollection", "features": features}, ensure_ascii=False).encode()
            else:
                status, body = fetch(url.path, query)
        except urllib.error.HTTPError as e:
            status, body = e.code, e.read()
        except (OSError, ValueError, KeyError) as e:
            print(f"upstream error for {self.path}: {e!r}", file=sys.stderr, flush=True)
            status, body = 502, json.dumps({"message": str(e)}).encode()
        self.reply(status, body)

    def reply(self, status, body):
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass  # one line per GPS point otherwise


def selftest():
    tokyo = localize({"name": "東京", "street": "グランスタ東京;地下1階", "locality": "丸の内一丁目",
                      "district": "千代田区", "city": "東京都", "state": None})
    assert (tokyo["city"], tokyo["state"], tokyo["street"], tokyo["housenumber"]) == \
        ("千代田区", "東京都", "丸の内一丁目", None), tokyo
    skytree = localize({"street": "1", "housenumber": "2", "locality": "押上一丁目",
                        "district": "墨田区", "city": "墨田区", "state": "東京都"})
    assert (skytree["city"], skytree["street"], skytree["housenumber"]) == ("墨田区", "押上一丁目", "1-2"), skytree
    hachioji = localize({"street": "野猿街道", "locality": "旭町", "district": "八王子市", "city": "東京都"})
    assert (hachioji["city"], hachioji["street"], hachioji["housenumber"]) == ("八王子市", "旭町", None), hachioji
    yokohama = localize({"street": "横浜西口", "locality": "相鉄ジョイナス地下街", "district": "西区",
                         "city": "横浜市", "state": "神奈川県"})
    assert yokohama["city"] == "横浜市", yokohama
    sapporo = localize({"name": "北6条西3丁目", "district": "北区", "city": "札幌市", "state": "北海道"})
    assert "street" not in sapporo and sapporo["city"] == "札幌市", sapporo
    towns = {"東京都": [("東和四丁目", "足立区", 35.773291, 139.841935), ("谷中一丁目", "葛飾区", 35.7700, 139.8500),
                       ("丸の内一丁目", "千代田区", 35.6813, 139.7671)]}
    towa = localize({"street": "蒲原通り", "locality": "東和四丁目", "district": "東和", "city": "東京都"},
                    [139.8390, 35.7760], towns)
    assert (towa["city"], towa["state"], towa["street"]) == ("足立区", "東京都", "東和四丁目"), towa
    # No 町丁目 of that name: nearest within NEAREST_ONLY_KM, and nothing from across the prefecture.
    near = localize({"locality": "どこか", "district": "東和", "city": "東京都"}, [139.8420, 35.7735], towns)
    assert near["city"] == "足立区", near
    far = localize({"locality": "どこか", "district": "奥多摩", "city": "東京都"}, [139.1000, 35.8000], towns)
    assert far["city"] == "奥多摩", far
    # Abroad: the nearest GeoNames town, never a Japanese one.
    cells = {(37, -123): [("San Francisco", "California", "United States", "US", 37.77493, -122.41942)],
             (37, -122): [("Oakland", "California", "United States", "US", 37.80437, -122.27080),
                          ("Palo Alto", "California", "United States", "US", 37.44188, -122.14302)]}
    sf = place_features(37.7790, -122.4190, cells)["features"][0]["properties"]
    assert (sf["city"], sf["state"], sf["country"], sf["countrycode"]) == \
        ("San Francisco", "California", "United States", "US"), sf
    assert place_features(37.4300, -122.1600, cells)["features"][0]["properties"]["city"] == "Palo Alto"
    assert place_features(0.0, 0.0, cells)["features"] == []
    assert in_japan(35.68, 139.77) and in_japan(26.21, 127.68) and not in_japan(37.77, -122.42)
    print("ok")


if __name__ == "__main__":
    if sys.argv[1:] == ["--selftest"]:
        selftest()
    else:
        TOWNS.update(load_towns())
        print(f"isj: {sum(map(len, TOWNS.values()))} 町丁目 in {len(TOWNS)} prefectures", file=sys.stderr, flush=True)
        try:
            PLACES.update(load_places())
        except (OSError, zipfile.BadZipFile) as e:
            print(f"geonames: {e!r}", file=sys.stderr, flush=True)  # abroad stays unnamed until a restart
        print(f"geonames: {sum(map(len, PLACES.values()))} towns", file=sys.stderr, flush=True)
        ThreadingHTTPServer(("0.0.0.0", 2323), Handler).serve_forever()
