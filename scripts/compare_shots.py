#!/usr/bin/env python3
"""Pixel-compare two screenshot series.

Usage: compare_shots.py <dir> <tagA> <tagB> [--mask X0,Y0,X1,Y1] [--expect-masked-diff]

--mask ignores one rectangle (pixels X0..X1-1, Y0..Y1-1), e.g. the remix
title-menu lines.  With --expect-masked-diff the comparison also fails unless
at least one frame differs inside the mask (proves the masked content exists).
"""
import argparse
import pathlib
import sys
from PIL import Image, ImageChops, ImageDraw

ap = argparse.ArgumentParser()
ap.add_argument("dir")
ap.add_argument("a")
ap.add_argument("b")
ap.add_argument("--mask")
ap.add_argument("--expect-masked-diff", action="store_true")
args = ap.parse_args()
d, a, b = pathlib.Path(args.dir), args.a, args.b
mask = tuple(int(v) for v in args.mask.split(",")) if args.mask else None


def blank(img):
    img = img.copy()
    ImageDraw.Draw(img).rectangle((mask[0], mask[1], mask[2] - 1, mask[3] - 1), fill=(0, 0, 0))
    return img


files = sorted(d.glob(f"{a}_[0-9][0-9][0-9].png"))
if not files:
    sys.exit(f"no screenshots for {a}")
bad, masked_only = [], 0
for fa in files:
    fb = d / fa.name.replace(a, b, 1)
    if not fb.exists():
        bad.append(f"{fb.name} missing")
        continue
    ia, ib = Image.open(fa).convert("RGB"), Image.open(fb).convert("RGB")
    if not ImageChops.difference(ia, ib).getbbox():
        continue
    if mask and not ImageChops.difference(blank(ia), blank(ib)).getbbox():
        masked_only += 1
        continue
    bad.append(fa.name.split("_")[-1])
msg = f"{len(files)} frames compared, {len(bad)} differ"
if mask:
    msg += f" outside the mask ({masked_only} differ only inside it)"
print(msg + (f": {', '.join(bad[:20])}" if bad else ""))
sys.exit(1 if bad or (args.expect_masked_diff and not masked_only) else 0)
