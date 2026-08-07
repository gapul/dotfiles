#!/usr/bin/env python3
"""Bake the world coastline into two packed uint32 tables for the MSL wallpapers.

  SDF_TABLE   signed distance to the coastline, u8, +/- SDF_RANGE table cells
  PHASE_TABLE cyclic arc-length along the nearest coastline, u8, 1.0 = one pulse
              cycle; continuous around each closed contour so a shader can run
              lights along the outline with `fract(phase - speed * time)`.

Both are equirectangular, 512x256, row 0 at +90 deg, x wrapping at +/-180 deg,
packed 4 cells per uint32 (x-major, little end first).

    curl -LO https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_50m_land.geojson
    uv run --with numpy,scipy,pillow,scikit-image python bake_world_sdf.py \
        ne_50m_land.geojson tables.txt

Then paste tables.txt above the shader body (see the header of worldmap.metal).
"""
import json
import sys

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage
from scipy.spatial import cKDTree
from skimage import measure

SRC = sys.argv[1] if len(sys.argv) > 1 else "ne50_land.geojson"
OUT = sys.argv[2] if len(sys.argv) > 2 else "tables.txt"
TW, TH = 512, 256      # table grid
SS = 8                 # supersample factor for the rasterisation
RANGE = 12.0           # +/- clamp of the stored distance, in table cells
SPACING = 140.0        # target arc length of one pulse cycle, in table cells


def rings(geom):
    if geom["type"] == "Polygon":
        yield geom["coordinates"]
    elif geom["type"] == "MultiPolygon":
        for poly in geom["coordinates"]:
            yield poly


def rasterize():
    feats = json.load(open(SRC))["features"]
    W, H = TW * SS, TH * SS
    img = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(img)
    for f in feats:
        for poly in rings(f["geometry"]):
            for i, ring in enumerate(poly):
                pts = [((lon + 180.0) / 360.0 * W, (90.0 - lat) / 180.0 * H)
                       for lon, lat, *_ in ring]
                if len(pts) >= 3:
                    d.polygon(pts, fill=255 if i == 0 else 0)
    return np.array(img) > 127


def bake_sdf(land):
    d_out = ndimage.distance_transform_edt(~land)
    d_in = ndimage.distance_transform_edt(land)
    sdf_hi = (d_out - d_in) / SS                       # table cells
    return sdf_hi.reshape(TH, SS, TW, SS).mean(axis=(1, 3))


def bake_phase(land):
    """Nearest-coastline cyclic arc length, in cycles."""
    pts, phase = [], []
    for c in measure.find_contours(land.astype(float), 0.5):
        c = c / SS                                     # -> table cells (row, col)
        if len(c) < 8:
            continue
        closed = np.allclose(c[0], c[-1])
        if closed:
            c = c[:-1]
        # Consistent handedness (positive shoelace area) so every landmass's
        # lights travel the same way round.
        y, x = c[:, 0], c[:, 1]
        if np.dot(x, np.roll(y, -1)) - np.dot(y, np.roll(x, -1)) < 0:
            c = c[::-1]
            y, x = c[:, 0], c[:, 1]
        seg = np.hypot(np.diff(x, append=x[0]), np.diff(y, append=y[0]))
        s = np.concatenate([[0.0], np.cumsum(seg)[:-1]])
        length = seg.sum()
        if length < 1.0:
            continue
        # An integer number of cycles round the loop keeps the phase continuous
        # across the seam.
        k = max(1.0, round(length / SPACING))
        pts.append(np.stack([x, y], axis=1))
        phase.append(s / length * k)
    pts = np.concatenate(pts)
    phase = np.concatenate(phase) % 1.0
    print(f"contour points {len(pts)}")

    # Wrap in longitude by repeating the point set either side of the seam.
    allp = np.concatenate([pts, pts + [TW, 0], pts - [TW, 0]])
    allph = np.concatenate([phase, phase, phase])
    tree = cKDTree(allp)
    gy, gx = np.mgrid[0:TH, 0:TW]
    q = np.stack([gx.ravel() + 0.5, gy.ravel() + 0.5], axis=1)
    _, idx = tree.query(q, workers=-1)
    return allph[idx].reshape(TH, TW)


def pack(u8):
    f = u8.reshape(-1).astype(np.uint32)
    return f[0::4] | (f[1::4] << 8) | (f[2::4] << 16) | (f[3::4] << 24)


def emit(fh, name, packed):
    fh.write(f"constant uint {name}[{len(packed)}] = {{\n")
    for i in range(0, len(packed), 8):
        fh.write("    " + " ".join(f"0x{v:08x}u," for v in packed[i:i + 8]) + "\n")
    fh.write("};\n\n")


def main():
    land = rasterize()
    print(f"raster {land.shape[1]}x{land.shape[0]}, land fraction {land.mean():.3f}")

    sdf = bake_sdf(land)
    sdf_u8 = np.rint((np.clip(sdf / RANGE, -1, 1) * 0.5 + 0.5) * 255).astype(np.uint8)

    ph = bake_phase(land)
    ph_u8 = np.rint(ph * 256.0).astype(np.int32) % 256

    with open(OUT, "w") as fh:
        fh.write(f"constant uint  SDF_W     = {TW}u;\n")
        fh.write(f"constant uint  SDF_H     = {TH}u;\n")
        fh.write(f"constant float SDF_RANGE = {RANGE};   // table cells\n")
        fh.write(f"constant float SPACING   = {SPACING};   // table cells per pulse cycle\n\n")
        emit(fh, "SDF_TABLE", pack(sdf_u8))
        emit(fh, "PHASE_TABLE", pack(ph_u8))
    print(f"wrote {OUT}")


main()
