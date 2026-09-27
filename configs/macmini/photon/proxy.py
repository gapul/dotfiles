"""Photon-compatible proxy in front of the local photon, for Dawarich on the homeserver.

Dawarich always asks photon for lang=en and reads only properties.city / street / housenumber.
In Japan that gives "Koto" and "Bunkyo", files every Tokyo ward and Tokyo city under 東京都
(photon puts the ward in `district`, which Dawarich never reads), and turns addresses into the
nearest road name, because OSM Japan addresses by block, not by street. So for results in
Japan this asks for the local language and moves the fields to where Dawarich looks; anywhere
else the request goes through untouched, English and all.

    python3 proxy.py              serve on :2323, upstream photon on 127.0.0.1:2322
    python3 proxy.py --selftest   check the Japanese rewrite against real photon output
"""

import json
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

UPSTREAM = "http://127.0.0.1:2322"
PREFECTURE = re.compile(r"[都道府県]$")


def localize(props):
    """Rewrite one Japanese photon feature's properties in place."""
    city, district = props.get("city"), props.get("district")
    # 東京都/千代田区 and 東京都/八王子市: the municipality is in district.
    # 横浜市/西区 already has the municipality in city and stays as it is.
    if city and district and PREFECTURE.search(city):
        props["state"] = props.get("state") or city
        props["city"] = district
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


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        url = urllib.parse.urlsplit(self.path)
        query = urllib.parse.parse_qs(url.query)
        try:
            status, body = fetch(url.path, {**query, "lang": ["default"]})
            features = json.loads(body).get("features") or []
            if features and features[0]["properties"].get("countrycode") == "JP":
                for f in features:
                    if f["properties"].get("countrycode") == "JP":
                        localize(f["properties"])
                body = json.dumps({"type": "FeatureCollection", "features": features}, ensure_ascii=False).encode()
            else:
                status, body = fetch(url.path, query)
        except urllib.error.HTTPError as e:
            status, body = e.code, e.read()
        except (OSError, ValueError, KeyError) as e:
            print(f"upstream error for {self.path}: {e!r}", file=sys.stderr, flush=True)
            status, body = 502, json.dumps({"message": str(e)}).encode()
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
    print("ok")


if __name__ == "__main__":
    if sys.argv[1:] == ["--selftest"]:
        selftest()
    else:
        ThreadingHTTPServer(("0.0.0.0", 2323), Handler).serve_forever()
