#!/bin/sh
# Build ~/.local/share/overture/japan.sqlite (places + addresses in Japan) from the newest Overture
# Maps release, for the maps MCP (configs/macmini/maps-mcp). Overture publishes about monthly; the
# launchd agent in nix/hosts/macmini.nix runs this on the 2nd of each month. DuckDB reads only the
# row groups whose bbox falls in Japan straight from the public S3 bucket, so nothing is mirrored.
# The previous database stays in place until the new one is complete, then the symlink flips.
set -eu
DIR="$HOME/.local/share/overture"
mkdir -p "$DIR"
cd "$DIR"
REL="${1:-$(duckdb -noheader -list -c "INSTALL httpfs; LOAD httpfs; SET s3_region='us-west-2';
  SELECT max(regexp_extract(file, 'release/([^/]+)/', 1)) FROM glob('s3://overturemaps-us-west-2/release/*/theme=places/type=place/part-00000*');")}"
OUT="$DIR/japan-$REL.sqlite"
if [ -e "$OUT" ] && [ "$(readlink japan.sqlite)" = "$OUT" ]; then
  echo "already on $REL"
  exit 0
fi
rm -f "$OUT.tmp"
duckdb <<SQL
INSTALL httpfs; LOAD httpfs; INSTALL sqlite; LOAD sqlite; SET s3_region='us-west-2';
ATTACH '$OUT.tmp' AS db (TYPE sqlite);
CREATE TABLE db.places AS
SELECT id, names.primary AS name, basic_category AS category, taxonomy.primary AS taxonomy,
       round(confidence, 3) AS confidence, operating_status AS status,
       websites[1] AS website, phones[1] AS phone, socials[1] AS social,
       addresses[1].freeform AS address, addresses[1].locality AS locality, addresses[1].region AS region,
       brand.names.primary AS brand,
       round((bbox.ymin + bbox.ymax) / 2, 6) AS lat, round((bbox.xmin + bbox.xmax) / 2, 6) AS lon
FROM read_parquet('s3://overturemaps-us-west-2/release/$REL/theme=places/type=place/*')
WHERE bbox.xmin BETWEEN 122 AND 154 AND bbox.ymin BETWEEN 20 AND 46
  AND (addresses IS NULL OR addresses[1].country IS NULL OR addresses[1].country = 'JP');
CREATE TABLE db.addresses AS
SELECT number, street, address_levels[1].value AS pref, address_levels[2].value AS city, postcode,
       round((bbox.ymin + bbox.ymax) / 2, 6) AS lat, round((bbox.xmin + bbox.xmax) / 2, 6) AS lon
FROM read_parquet('s3://overturemaps-us-west-2/release/$REL/theme=addresses/type=address/*')
WHERE bbox.xmin BETWEEN 122 AND 154 AND bbox.ymin BETWEEN 20 AND 46;
SQL
sqlite3 "$OUT.tmp" <<SQL
CREATE INDEX places_latlon ON places(lat, lon);
CREATE INDEX addresses_latlon ON addresses(lat, lon);
CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT);
INSERT INTO meta VALUES ('release', '$REL'), ('built_at', datetime('now'));
ANALYZE;
SQL
mv "$OUT.tmp" "$OUT"
ln -sfn "$OUT" japan.sqlite
find "$DIR" -maxdepth 1 -name 'japan-*.sqlite' ! -name "japan-$REL.sqlite" -delete
echo "built $REL: $(du -h "$OUT" | cut -f1)"
