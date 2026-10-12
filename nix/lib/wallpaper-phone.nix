{
  pkgs,
  lib ? pkgs.lib,
  p,
  name,
  # The picture: any public-domain scan (url + sha256 for fetchurl), and the part of it to
  # use, as fractions (left, top, right, bottom). Default: Hiroshige's Ōhashi rain.
  source ? {
    url = "https://upload.wikimedia.org/wikipedia/commons/7/72/Hiroshige%2C_Sudden_shower_over_Shin-%C5%8Chashi_bridge_and_Atake%2C_1857.jpg";
    sha256 = "1yci11zx75hr1icvp05f1jmcr6bq74h3piz0j3a2a4xgmn6dsdm2";
  },
  crop ? [ 0.035 0.012 0.965 0.985 ],
  # iPhone Pro portrait canvas; cells scaled for it.
  width ? 1290,
  height ? 2796,
  fontSize ? 8,
  # Grey level (0..1 after contrast stretch) above which a cell stays empty; lower = only
  # the darkest things (rain, timbers, the night sky and river) become characters.
  threshold ? 0.6,
  # Dark lines (the rain, the timbers) are thinner than a cell; a minimum filter of this
  # size on the full-resolution print thickens them so they survive the downscale.
  thicken ? 9,
  # Local contrast: 0 = off; otherwise the radius (in cells) of the blur subtracted from the
  # picture before the threshold. Engravings and etchings are hatched all over, so by
  # plain darkness every cell fills; relative to their surroundings, the lines stand out.
  highpass ? 0,
  highpassGain ? 2.0,
}:
# A portrait wallpaper for the phone in the palette `p`: Hiroshige's "Sudden Shower over
# Shin-Ōhashi Bridge and Atake" (Meisho Edo hyakkei, 1857; the Wikimedia Commons scan,
# public domain) as ASCII art, the same way as the desktop's (wallpaper-wave.nix): the
# print's dark areas become characters, so the rain, the bridge's timbers and the dark sky
# and river carry the picture. Fitted by width; the base colour fills above and below.
let
  # `source` is fetched, or, when it carries a `path`, used as it is (e.g. a file already in
  # the store, to spare Wikimedia another download).
  picture = source.path or (pkgs.fetchurl { inherit (source) url sha256; });
  python = pkgs.python3.withPackages (ps: [ ps.pillow ]);
  fontPackage = pkgs.nerd-fonts.jetbrains-mono;
  render = pkgs.writeText "ascii-rain.py" ''
    import sys
    from PIL import Image, ImageDraw, ImageFont, ImageOps, ImageFilter

    src, font_path, variant, base, text, muted, out, w, h, font_size, threshold, thicken, crop, highpass, hp_gain = sys.argv[1:16]
    W, H, FONT_SIZE, THRESHOLD, THICKEN = int(w), int(h), int(font_size), float(threshold), int(thicken)
    HIGHPASS, HP_GAIN = int(highpass), float(hp_gain)
    cx0, cy0, cx1, cy1 = (float(x) for x in crop.split(","))
    RAMP = " .,:;-~=+*xkX%#@"

    def rgb(hx):
        return tuple(int(hx[i:i + 2], 16) for i in (0, 2, 4))

    base_c, text_c, muted_c = rgb(base), rgb(text), rgb(muted)
    font = ImageFont.truetype(font_path, FONT_SIZE)
    cw = font.getlength("M")
    ch = FONT_SIZE * 1.05
    cols, rows = int(W / cw), int(H / ch)

    img = Image.open(src).convert("L")
    img = img.crop((int(img.width * cx0), int(img.height * cy0), int(img.width * cx1), int(img.height * cy1)))
    img = ImageOps.autocontrast(img, cutoff=1)
    if THICKEN > 1:
        img = img.filter(ImageFilter.MinFilter(THICKEN))
    fit_cols = cols
    fit_rows = int(fit_cols * (img.height / img.width) * (cw / ch))
    if fit_rows > rows:
        fit_rows = rows
        fit_cols = int(fit_rows * (img.width / img.height) * (ch / cw))
    small = img.resize((fit_cols, fit_rows), Image.LANCZOS)
    px = small.load()
    blurred = small.filter(ImageFilter.GaussianBlur(HIGHPASS)).load() if HIGHPASS > 0 else None

    def fade(i, n, width):
        e = min(i, n - 1 - i)
        return min(1.0, e / width) if width > 0 else 1.0

    canvas = Image.new("RGB", (W, H), base_c)
    d = ImageDraw.Draw(canvas)
    x0 = (cols - fit_cols) // 2
    y0 = (rows - fit_rows) // 2
    n = len(RAMP)
    for j in range(fit_rows):
        for i in range(fit_cols):
            v = px[i, j] / 255.0
            if blurred is not None:
                v = max(0.0, min(1.0, 0.5 + (v - blurred[i, j] / 255.0) * HP_GAIN))
            # Dark = dense, as for the desktop; the light water in the middle stays sparse.
            density = max(0.0, min(1.0, (THRESHOLD - v) / (THRESHOLD * 0.8))) ** 0.9
            density *= fade(i, fit_cols, fit_cols * 0.04) * fade(j, fit_rows, fit_rows * 0.03)
            k = int(density * (n - 1) + 0.5)
            if k == 0:
                continue
            t = k / (n - 1)
            colour = tuple(int(muted_c[c] + (text_c[c] - muted_c[c]) * t) for c in range(3))
            d.text(((x0 + i) * cw, (y0 + j) * ch), RAMP[k], fill=colour, font=font)
    canvas.save(out, "PNG", optimize=True)
  '';
in
pkgs.runCommand "${name}-phone.png" { nativeBuildInputs = [ python ]; } ''
  font=$(find ${fontPackage}/share/fonts -name 'JetBrainsMonoNerdFontMono-Regular.ttf' | head -n 1)
  python3 ${render} ${picture} "$font" ${p.variant} ${p.base} ${p.text} ${p.muted} $out ${toString width} ${toString height} ${toString fontSize} ${toString threshold} ${toString thicken} ${lib.concatMapStringsSep "," toString crop} ${toString highpass} ${toString highpassGain}
''
