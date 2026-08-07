#!/bin/sh
# assemble.sh <body.metal> <out.metal> — replace the // __TABLES__ line in a
# shader body with the tables baked by bake_world_sdf.py.
set -e
cd "$(dirname "$0")"
awk '/^\/\/ __TABLES__$/ { while ((getline line < "tables.txt") > 0) print line; next } { print }' "$1" > "$2"
