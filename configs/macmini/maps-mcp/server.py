"""Read-only maps MCP server for Claude, on the macmini (Streamable HTTP, JSON responses).

One endpoint gives every Claude on the tailnet the map knowledge Google Maps would otherwise
supply, from sources that stay ours or open (see the maps memory for why each was chosen):

    geocode / reverse_geocode   local photon via photon-proxy (:2323) + GSI address search
                                + Overture addresses (block-level 番地) from the local SQLite
    nearby_places               Overture places (Japan) from the local SQLite
    apple_search / apple_route  Apple Maps Server API (key in ~/.config/apple-maps, 25k calls/day)
    transit_route               Transitous (open MOTIS instance; Google's API returns nothing in Japan)
    web_search                  self-hosted SearXNG; google + google cse is an anonymous Google search
    weather                     Open-Meteo

Everything is stdlib: the ES256 JWT for Apple is signed by the system openssl (LibreSSL),
and the Overture database is plain sqlite3. Nothing here writes anywhere.

    python3 server.py              serve on :2324 (POST /mcp)
    python3 server.py --selftest   call every tool against the live services
"""

import base64
import json
import math
import os
import sqlite3
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

PORT = 2324
HOME = Path.home()
PHOTON = os.environ.get("PHOTON_URL", "http://127.0.0.1:2323")
SEARXNG = os.environ.get("SEARXNG_URL", "https://search.gapul.net")
TRANSITOUS = "https://api.transitous.org/api/v5/plan"
OVERTURE_DB = HOME / ".local/share/overture/japan.sqlite"
APPLE_DIR = HOME / ".config/apple-maps"
UA = "gapul-maps-mcp/1.0 (+https://gapul.net)"
TIMEOUT = 20


def http_json(url, headers=None):
    req = urllib.request.Request(url, headers={"User-Agent": UA, **(headers or {})})
    with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
        return json.load(r)


def km(lat1, lon1, lat2, lon2):
    return math.hypot(lat2 - lat1, (lon2 - lon1) * math.cos(math.radians(lat1))) * 111.2


# --- Apple Maps Server API -------------------------------------------------------------------

_apple = {"token": None, "until": 0.0}
_apple_lock = threading.Lock()


def _env(path):
    return dict(l.split("=", 1) for l in path.read_text().splitlines() if "=" in l)


def apple_token():
    with _apple_lock:
        if _apple["token"] and time.time() < _apple["until"]:
            return _apple["token"]
        env = _env(APPLE_DIR / "env")
        b64 = lambda b: base64.urlsafe_b64encode(b).rstrip(b"=").decode()
        now = int(time.time())
        head = b64(json.dumps({"alg": "ES256", "kid": env["APPLE_MAPS_KEY_ID"], "typ": "JWT"}).encode())
        body = b64(json.dumps({"iss": env["APPLE_MAPS_TEAM_ID"], "iat": now, "exp": now + 1800}).encode())
        der = subprocess.run(["/usr/bin/openssl", "dgst", "-sha256", "-sign", env["APPLE_MAPS_KEY_PATH"]],
                             input=f"{head}.{body}".encode(), capture_output=True, check=True).stdout
        asn = subprocess.run(["/usr/bin/openssl", "asn1parse", "-inform", "DER"],
                             input=der, capture_output=True, check=True).stdout.decode()
        ints = [l.rsplit(":", 1)[-1] for l in asn.splitlines() if "INTEGER" in l]
        sig = b"".join(bytes.fromhex(i).rjust(32, b"\0")[-32:] for i in ints)
        tok = http_json("https://maps-api.apple.com/v1/token", {"Authorization": f"Bearer {head}.{body}.{b64(sig)}"})
        _apple.update(token=tok["accessToken"], until=time.time() + int(tok.get("expiresInSeconds", 1800)) - 120)
        return _apple["token"]


def apple(path, **params):
    q = urllib.parse.urlencode({k: v for k, v in params.items() if v is not None})
    return http_json(f"https://maps-api.apple.com{path}?{q}", {"Authorization": f"Bearer {apple_token()}"})


def place_brief(p):
    return {"name": p.get("name"), "category": p.get("poiCategory"),
            "address": " ".join(p.get("formattedAddressLines") or []),
            "lat": p.get("coordinate", {}).get("latitude"), "lon": p.get("coordinate", {}).get("longitude")}


def apple_search(query, near_lat=None, near_lon=None, limit=5):
    near = f"{near_lat},{near_lon}" if near_lat is not None and near_lon is not None else None
    res = apple("/v1/search", q=query, searchLocation=near, lang="ja-JP")
    return [place_brief(p) for p in res.get("results", [])[:limit]]


def apple_route(from_lat, from_lon, to_lat, to_lon, mode="Automobile", depart_at=None):
    res = apple("/v1/directions", origin=f"{from_lat},{from_lon}", destination=f"{to_lat},{to_lon}",
                transportType=mode, departureDate=depart_at, lang="ja-JP", requestsAlternateRoutes="true")
    steps = res.get("steps", [])
    out = []
    for r in res.get("routes", [])[:3]:
        out.append({"name": r.get("name"), "distance_km": round(r.get("distanceMeters", 0) / 1000, 2),
                    "duration_min": round(r.get("durationSeconds", 0) / 60), "has_tolls": r.get("hasTolls"),
                    "steps": [steps[i].get("instructions") for i in r.get("stepIndexes", [])
                              if i < len(steps) and steps[i].get("instructions")][:25]})
    return out


# --- photon / GSI / Overture -----------------------------------------------------------------

def geocode(query, near_lat=None, near_lon=None, limit=5):
    params = {"q": query, "limit": limit}
    if near_lat is not None and near_lon is not None:
        params.update(lat=near_lat, lon=near_lon)
    out = {"photon": [], "gsi": []}
    for f in http_json(f"{PHOTON}/api?{urllib.parse.urlencode(params)}").get("features", []):
        p = f["properties"]
        out["photon"].append({"name": p.get("name"), "kind": f"{p.get('osm_key')}={p.get('osm_value')}",
                              "address": " ".join(x for x in (p.get("state"), p.get("city"), p.get("street"),
                                                              p.get("housenumber")) if x),
                              "lat": f["geometry"]["coordinates"][1], "lon": f["geometry"]["coordinates"][0]})
    try:
        gsi = http_json("https://msearch.gsi.go.jp/address-search/AddressSearch?" + urllib.parse.urlencode({"q": query}))
        out["gsi"] = [{"title": g["properties"]["title"], "lat": g["geometry"]["coordinates"][1],
                       "lon": g["geometry"]["coordinates"][0]} for g in gsi[:limit]]
    except (OSError, ValueError, KeyError):
        pass  # GSI is a second opinion for addresses; photon already answered
    return out


def db():
    con = sqlite3.connect(f"file:{OVERTURE_DB}?mode=ro", uri=True, check_same_thread=False)
    con.row_factory = sqlite3.Row
    return con


def _box(lat, lon, radius_m):
    dlat = radius_m / 111200
    dlon = dlat / max(math.cos(math.radians(lat)), 0.01)
    return lat - dlat, lat + dlat, lon - dlon, lon + dlon


def reverse_geocode(lat, lon):
    out = {"photon": None, "nearest_address": None}
    feats = http_json(f"{PHOTON}/reverse?{urllib.parse.urlencode({'lat': lat, 'lon': lon})}").get("features", [])
    if feats:
        p = feats[0]["properties"]
        out["photon"] = {k: p.get(k) for k in ("name", "state", "city", "street", "housenumber", "postcode", "country")}
    if OVERTURE_DB.exists():
        a, b, c, d = _box(lat, lon, 60)
        rows = db().execute("SELECT pref, city, street, number, lat, lon FROM addresses "
                            "WHERE lat BETWEEN ? AND ? AND lon BETWEEN ? AND ?", (a, b, c, d)).fetchall()
        if rows:
            r = min(rows, key=lambda r: km(lat, lon, r["lat"], r["lon"]))
            out["nearest_address"] = {"address": f"{r['pref'] or ''}{r['city'] or ''}{r['street'] or ''}{r['number'] or ''}",
                                      "distance_m": round(km(lat, lon, r["lat"], r["lon"]) * 1000)}
    return out


def nearby_places(lat, lon, radius_m=500, keyword=None, category=None, min_confidence=0.7, limit=20):
    if not OVERTURE_DB.exists():
        raise RuntimeError("Overture database not built yet (~/.local/share/overture/build.sh)")
    a, b, c, d = _box(lat, lon, radius_m)
    sql = ("SELECT name, category, confidence, phone, website, address, brand, lat, lon FROM places "
           "WHERE lat BETWEEN ? AND ? AND lon BETWEEN ? AND ? AND confidence >= ?")
    args = [a, b, c, d, min_confidence]
    if keyword:
        sql += " AND (name LIKE ? OR brand LIKE ?)"
        args += [f"%{keyword}%"] * 2
    if category:
        sql += " AND (category LIKE ? OR taxonomy LIKE ?)"
        args += [f"%{category}%"] * 2
    rows = [dict(r) | {"distance_m": round(km(lat, lon, r["lat"], r["lon"]) * 1000)}
            for r in db().execute(sql, args).fetchall()]
    rows = [r for r in rows if r["distance_m"] <= radius_m]
    return sorted(rows, key=lambda r: r["distance_m"])[:limit]


# --- transit / search / weather --------------------------------------------------------------

def transit_route(from_lat, from_lon, to_lat, to_lon, time_iso=None, arrive_by=False, limit=4):
    params = {"fromPlace": f"{from_lat},{from_lon}", "toPlace": f"{to_lat},{to_lon}"}
    if time_iso:
        params.update(time=time_iso, arriveBy=str(bool(arrive_by)).lower())
    res = http_json(f"{TRANSITOUS}?{urllib.parse.urlencode(params)}")
    out = []
    for it in (res.get("itineraries") or [])[:limit]:
        legs = []
        for l in it.get("legs", []):
            leg = {"mode": l.get("mode"), "from": (l.get("from") or {}).get("name"), "to": (l.get("to") or {}).get("name"),
                   "depart": l.get("startTime"), "arrive": l.get("endTime"), "minutes": round(l.get("duration", 0) / 60)}
            if l.get("mode") != "WALK":
                leg.update(line=l.get("routeShortName"), agency=l.get("agencyName"), headsign=l.get("headsign"))
            legs.append(leg)
        out.append({"minutes": round(it.get("duration", 0) / 60), "depart": it.get("startTime"),
                    "arrive": it.get("endTime"), "transfers": it.get("transfers"), "legs": legs})
    return {"itineraries": out, "attribution": "https://transitous.org/sources/"}


def web_search(query, engines="google,google cse", limit=8):
    res = http_json(f"{SEARXNG}/search?{urllib.parse.urlencode({'q': query, 'format': 'json', 'engines': engines})}")
    return {"results": [{"title": r.get("title"), "url": r.get("url"), "snippet": (r.get("content") or "")[:300],
                         "engine": r.get("engine")} for r in res.get("results", [])[:limit]],
            "unresponsive": res.get("unresponsive_engines")}


def weather(lat, lon, days=2):
    q = urllib.parse.urlencode({"latitude": lat, "longitude": lon, "timezone": "Asia/Tokyo", "forecast_days": days,
                                "hourly": "temperature_2m,precipitation_probability,precipitation,weather_code",
                                "daily": "temperature_2m_max,temperature_2m_min,precipitation_probability_max,weather_code"})
    return http_json(f"https://api.open-meteo.com/v1/forecast?{q}")


# --- MCP plumbing ----------------------------------------------------------------------------

NUM = {"type": "number"}
STR = {"type": "string"}
TOOLS = {
    "geocode": (geocode, "Place name or address → coordinates. Local photon (OSM, Japanese) plus the GSI "
                "official address search. Pass near_lat/near_lon to bias towards an area.",
                {"query": STR, "near_lat": NUM, "near_lon": NUM, "limit": {"type": "integer"}}, ["query"]),
    "reverse_geocode": (reverse_geocode, "Coordinates → address. photon gives the 町丁目; Overture adds the "
                        "nearest block-level 番地 within 60 m.", {"lat": NUM, "lon": NUM}, ["lat", "lon"]),
    "nearby_places": (nearby_places, "Shops, restaurants, cafes etc. around a point from Overture Maps "
                      "(Japan, ~2.9M places, has phone/website, no opening hours or reviews). Filter by keyword "
                      "(name/brand) or category (e.g. cafe, restaurant, coffee_shop, bar).",
                      {"lat": NUM, "lon": NUM, "radius_m": NUM, "keyword": STR, "category": STR,
                       "min_confidence": NUM, "limit": {"type": "integer"}}, ["lat", "lon"]),
    "apple_search": (apple_search, "Apple Maps place search (name, category, address, coordinates). Good "
                     "general-purpose place lookup.", {"query": STR, "near_lat": NUM, "near_lon": NUM,
                                                        "limit": {"type": "integer"}}, ["query"]),
    "apple_route": (apple_route, "Apple Maps directions with traffic-aware duration. mode: Automobile, Walking "
                    "or Cycling (no transit — use transit_route). depart_at: ISO 8601 UTC.",
                    {"from_lat": NUM, "from_lon": NUM, "to_lat": NUM, "to_lon": NUM,
                     "mode": {"type": "string", "enum": ["Automobile", "Walking", "Cycling"]}, "depart_at": STR},
                    ["from_lat", "from_lon", "to_lat", "to_lon"]),
    "transit_route": (transit_route, "Public transport itineraries in Japan (Tokyo Metro, Toei, JR East, buses) "
                      "via Transitous. time_iso: ISO 8601 with offset; arrive_by makes it an arrival time. "
                      "Sometimes prefers a bus leg oddly; sanity-check.",
                      {"from_lat": NUM, "from_lon": NUM, "to_lat": NUM, "to_lon": NUM, "time_iso": STR,
                       "arrive_by": {"type": "boolean"}, "limit": {"type": "integer"}},
                      ["from_lat", "from_lon", "to_lat", "to_lon"]),
    "web_search": (web_search, "Web search through the self-hosted SearXNG. The default engines (google, google cse) are an "
                   "anonymous Google search (no account, only the home IP is visible); plain google is often "
                   "CAPTCHA-suspended for a while and google cse then answers. Use for opening hours, temporary closures, "
                   "reviews (tabelog for restaurants).", {"query": STR, "engines": STR, "limit": {"type": "integer"}},
                   ["query"]),
    "weather": (weather, "Weather forecast (Open-Meteo), hourly and daily, Asia/Tokyo.",
                {"lat": NUM, "lon": NUM, "days": {"type": "integer"}}, ["lat", "lon"]),
}


def tools_list():
    return [{"name": n, "description": d, "annotations": {"readOnlyHint": True},
             "inputSchema": {"type": "object", "properties": p, "required": r}}
            for n, (_, d, p, r) in TOOLS.items()]


def handle(msg):
    method, mid = msg.get("method"), msg.get("id")
    if mid is None:
        return None  # notification
    if method == "initialize":
        result = {"protocolVersion": msg.get("params", {}).get("protocolVersion", "2025-06-18"),
                  "capabilities": {"tools": {}}, "serverInfo": {"name": "maps", "version": "1.0"},
                  "instructions": "Read-only map tools: geocoding, nearby places (Overture), Apple Maps search and "
                                  "driving/walking/cycling routes, Japanese transit (Transitous), anonymous web "
                                  "search, weather. The user's own location history is in the separate dawarich MCP."}
    elif method == "ping":
        result = {}
    elif method == "tools/list":
        result = {"tools": tools_list()}
    elif method == "tools/call":
        name = msg["params"]["name"]
        args = msg["params"].get("arguments") or {}
        try:
            data = TOOLS[name][0](**args)
            result = {"content": [{"type": "text", "text": json.dumps(data, ensure_ascii=False)}]}
        except (KeyError, TypeError) as e:
            result = {"content": [{"type": "text", "text": f"bad request: {e!r}"}], "isError": True}
        except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError, sqlite3.Error) as e:
            detail = e.read().decode(errors="replace")[:300] if isinstance(e, urllib.error.HTTPError) else ""
            result = {"content": [{"type": "text", "text": f"{name} failed: {e!r} {detail}"}], "isError": True}
    else:
        return {"jsonrpc": "2.0", "id": mid, "error": {"code": -32601, "message": f"unknown method {method}"}}
    return {"jsonrpc": "2.0", "id": mid, "result": result}


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path.rstrip("/") != "/mcp":
            self.send_error(404)
            return
        try:
            msg = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))
        except ValueError:
            self.send_error(400)
            return
        reply = [r for r in map(handle, msg) if r] if isinstance(msg, list) else handle(msg)
        if not reply:
            self.send_response(202)
            self.end_headers()
            return
        body = json.dumps(reply, ensure_ascii=False).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        self.send_response(405)  # no server-initiated stream; clients fall back to plain POST
        self.end_headers()

    def log_message(self, fmt, *args):
        print(f"{self.address_string()} {fmt % args}", file=sys.stderr, flush=True)


def selftest():
    k = (35.6818, 139.7989)  # 清澄白河
    h = (35.7071, 139.7606)  # 本郷三丁目
    assert geocode("清澄庭園")["photon"], "geocode"
    assert reverse_geocode(*k)["photon"], "reverse_geocode"
    if OVERTURE_DB.exists():
        assert nearby_places(*k, radius_m=400, category="cafe"), "nearby_places"
    assert apple_search("清澄庭園", *k), "apple_search"
    assert apple_route(*k, *h)[0]["duration_min"] > 0, "apple_route"
    assert transit_route(*k, *h)["itineraries"], "transit_route"
    assert web_search("清澄白河 カフェ")["results"], "web_search"
    assert weather(*k)["hourly"]["time"], "weather"
    assert {t["name"] for t in tools_list()} == set(TOOLS)
    print("ok" + ("" if OVERTURE_DB.exists() else " (nearby_places skipped: no Overture DB yet)"))


if __name__ == "__main__":
    if sys.argv[1:] == ["--selftest"]:
        selftest()
    else:
        ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
