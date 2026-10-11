{
  pkgs,
  p,
  name,
}:
# Wallpaper for the palette `p`: Michelangelo's "Creation of Adam" (the hands, the
# Wikimedia Commons crop, public domain) rendered as ASCII art in the palette's colours,
# after the look of the yabai rice at reddit.com/r/unixporn/comments/1x2zwou. The art is
# generated here rather than checked in, so a palette switch (dark/light) regenerates it:
# light characters on the dark base, dark characters on the light one. Rendered with the
# desktop's monospace face, so the characters match the terminal and the bar.
let
  source = pkgs.fetchurl {
    url = "https://upload.wikimedia.org/wikipedia/commons/5/5b/Michelangelo_-_Creation_of_Adam_%28cropped%29.jpg";
    sha256 = "0pq9dzgp388yajz5b3myc80p82zh7m5hpcvm4ajxz55frhv5zpl4";
  };
  python = pkgs.python3.withPackages (ps: [ ps.pillow ]);
  fontPackage = pkgs.nerd-fonts.jetbrains-mono;
  render = pkgs.writeText "ascii-wallpaper.py" ''
    import sys
    from PIL import Image, ImageDraw, ImageFont, ImageOps

    src, font_path, variant, base, text, muted, out = sys.argv[1:8]
    W, H = 3840, 2400
    FONT_SIZE = 15
    # From sparse to dense. The first entry is a space, so the darkest cells stay empty and
    # the background reads as a plain surface rather than a wall of dots.
    RAMP = " .,:;-~=+*xkX%#@"

    def rgb(h):
        return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))

    base_c, text_c, muted_c = rgb(base), rgb(text), rgb(muted)
    font = ImageFont.truetype(font_path, FONT_SIZE)
    bbox = font.getbbox("M")
    cw = font.getlength("M")
    ch = FONT_SIZE * 1.05
    cols, rows = int(W / cw), int(H / ch)

    img = Image.open(src).convert("L")
    # Only the two hands, not the whole fresco: the crop is in fractions of the picture.
    cx0, cy0, cx1, cy1 = 0.22, 0.29, 0.56, 0.59
    img = img.crop((int(img.width * cx0), int(img.height * cy0), int(img.width * cx1), int(img.height * cy1)))
    img = ImageOps.autocontrast(img, cutoff=1)
    # Fit the picture into the character grid with a margin, keeping its aspect once the
    # cells' own aspect (taller than wide) is taken into account.
    fit_cols = int(cols * 1.0)
    fit_rows = int(fit_cols * (img.height / img.width) * (cw / ch))
    if fit_rows > rows * 0.95:
        fit_rows = int(rows * 0.95)
        fit_cols = int(fit_rows * (img.width / img.height) * (ch / cw))
    small = img.resize((fit_cols, fit_rows), Image.LANCZOS)
    px = small.load()

    def fade(i, n, width):
        # 1 inside, falling to 0 over `width` cells at either edge, so the crop has no border.
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
            # The fresco's sky is the brightest thing in the crop; everything brighter than
            # the skin tones becomes empty, so the hands stand on the bare surface.
            density = max(0.0, min(1.0, (0.80 - v) / 0.55)) ** 0.75
            density *= fade(i, fit_cols, fit_cols * 0.06) * fade(j, fit_rows, fit_rows * 0.12)
            k = int(density * (n - 1) + 0.5)
            if k == 0:
                continue
            t = k / (n - 1)
            colour = tuple(int(muted_c[c] + (text_c[c] - muted_c[c]) * t) for c in range(3))
            d.text(((x0 + i) * cw, (y0 + j) * ch), RAMP[k], fill=colour, font=font)
    canvas.save(out, "PNG", optimize=True)
  '';
in
pkgs.runCommand "${name}-wallpaper.png" { nativeBuildInputs = [ python ]; } ''
  font=$(find ${fontPackage}/share/fonts -name 'JetBrainsMonoNerdFontMono-Regular.ttf' | head -n 1)
  python3 ${render} ${source} "$font" ${p.variant} ${p.base} ${p.text} ${p.muted} $out
''
