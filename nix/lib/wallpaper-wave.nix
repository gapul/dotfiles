{
  pkgs,
  p,
  name,
  variant ? "dark",
}:
# Wallpaper for the palette `p`: the wave of Hokusai's "The Great Wave off Kanagawa"
# (Fugaku sanjūrokkei; the Wikimedia Commons scan, public domain) as ASCII art in the
# palette's colours, made the same way as the Creation of Adam one (wallpaper-hands.nix).
# `variant`: "dark" draws the print's dark areas (the wave as a mass with the foam cut
# out, which reads as the print); "foam" draws the foam brightest from the colours.
let
  source = pkgs.fetchurl {
    url = "https://upload.wikimedia.org/wikipedia/commons/0/0a/The_Great_Wave_off_Kanagawa.jpg";
    sha256 = "01kjva7ka7ln8gy5s2zyfph8ywvfa03y91mmwqzhlczhpmm4ia24";
  };
  python = pkgs.python3.withPackages (ps: [ ps.pillow ]);
  fontPackage = pkgs.nerd-fonts.jetbrains-mono;
  render = pkgs.writeText "ascii-wave.py" ''
    import sys, colorsys
    from PIL import Image, ImageDraw, ImageFont, ImageOps

    src, font_path, variant, base, text, muted, out, how = sys.argv[1:9]
    W, H = 3840, 2400
    FONT_SIZE = 15
    RAMP = " .,:;-~=+*xkX%#@"

    def rgb(h):
        return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))

    base_c, text_c, muted_c = rgb(base), rgb(text), rgb(muted)
    font = ImageFont.truetype(font_path, FONT_SIZE)
    cw = font.getlength("M")
    ch = FONT_SIZE * 1.05
    cols, rows = int(W / cw), int(H / ch)

    img = Image.open(src).convert("RGB")
    # The whole print (Fuji, the boats, the cartouche), only the paper margin trimmed.
    cx0, cy0, cx1, cy1 = 0.01, 0.01, 0.99, 0.99
    img = img.crop((int(img.width * cx0), int(img.height * cy0), int(img.width * cx1), int(img.height * cy1)))
    fit_cols = cols
    fit_rows = int(fit_cols * (img.height / img.width) * (cw / ch))
    if fit_rows > rows * 0.96:
        fit_rows = int(rows * 0.96)
        fit_cols = int(fit_rows * (img.width / img.height) * (ch / cw))
    small = img.resize((fit_cols, fit_rows), Image.LANCZOS)
    gray = ImageOps.autocontrast(small.convert("L"), cutoff=1).load()
    px = small.load()

    def fade(i, n, width):
        e = min(i, n - 1 - i)
        return min(1.0, e / width) if width > 0 else 1.0

    def density_dark(i, j):
        # The print's dark areas (the Prussian-blue water and outlines) as characters,
        # the pale sky and the white foam empty: the wave as a mass with the foam cut out.
        v = gray[i, j] / 255.0
        return max(0.0, min(1.0, (0.78 - v) / 0.55)) ** 0.75

    def density_foam(i, j):
        # Foam brightest, water a mid texture, the sky empty, from the colours: foam is
        # near-white, the water is saturated blue, the sky a pale, unsaturated beige.
        r, g, b = (c / 255.0 for c in px[i, j])
        h, s, v = colorsys.rgb_to_hsv(r, g, b)
        if s < 0.14 and v > 0.86:
            return 1.0
        if s > 0.28 and 0.5 < h < 0.72:
            return 0.25 + 0.45 * (1.0 - v)
        if v < 0.35:
            return 0.8
        return 0.0

    canvas = Image.new("RGB", (W, H), base_c)
    d = ImageDraw.Draw(canvas)
    x0 = (cols - fit_cols) // 2
    y0 = (rows - fit_rows) // 2
    n = len(RAMP)
    pick = density_foam if how == "foam" else density_dark
    for j in range(fit_rows):
        for i in range(fit_cols):
            density = pick(i, j)
            density *= fade(i, fit_cols, fit_cols * 0.05) * fade(j, fit_rows, fit_rows * 0.1)
            k = int(density * (n - 1) + 0.5)
            if k == 0:
                continue
            t = k / (n - 1)
            colour = tuple(int(muted_c[c] + (text_c[c] - muted_c[c]) * t) for c in range(3))
            d.text(((x0 + i) * cw, (y0 + j) * ch), RAMP[k], fill=colour, font=font)
    canvas.save(out, "PNG", optimize=True)
  '';
in
pkgs.runCommand "${name}-wave-${variant}.png" { nativeBuildInputs = [ python ]; } ''
  font=$(find ${fontPackage}/share/fonts -name 'JetBrainsMonoNerdFontMono-Regular.ttf' | head -n 1)
  python3 ${render} ${source} "$font" ${p.variant} ${p.base} ${p.text} ${p.muted} $out ${variant}
''
