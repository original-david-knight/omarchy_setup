#!/usr/bin/env python3
"""Draw a theme's picker preview as a mock tiled desktop, from its colors.toml.

The stock Omarchy previews are screenshots of nvim, a terminal, btop and the
file manager tiled over the wallpaper. This draws the same arrangement from
invented content, so no real session data can reach the public repository.
Requires Pillow, CaskaydiaMono Nerd Font and the theme's Yaru icon set.
"""
import argparse
import json
import math
from pathlib import Path
import random
import tomllib

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
W, H = 1800, 1012
FONT_DIR = Path("/usr/share/fonts/TTF")


def rgb(value, alpha=255):
    value = value.lstrip("#")
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4)) + (alpha,)


def mix(a, b, amount):
    a, b = rgb(a), rgb(b)
    return tuple(round(a[i] * (1 - amount) + b[i] * amount) for i in range(3)) + (255,)


class Canvas:
    def __init__(self, image, colors):
        self.image = image
        self.draw = ImageDraw.Draw(image)
        self.c = colors
        self.font = ImageFont.truetype(str(FONT_DIR / "CaskaydiaMonoNerdFont-Regular.ttf"), 13)
        self.bold = ImageFont.truetype(str(FONT_DIR / "CaskaydiaMonoNerdFont-Bold.ttf"), 13)
        self.italic = ImageFont.truetype(str(FONT_DIR / "CaskaydiaMonoNerdFont-Italic.ttf"), 13)
        self.ui = ImageFont.truetype("/usr/share/fonts/liberation/LiberationSans-Regular.ttf", 15)
        self.ui_bold = ImageFont.truetype("/usr/share/fonts/liberation/LiberationSans-Bold.ttf", 15)
        self.glyphs = ImageFont.truetype(str(FONT_DIR / "CaskaydiaMonoNerdFont-Regular.ttf"), 15)
        self.cw = self.draw.textlength("M", font=self.font)
        self.lh = 15

    def color(self, name):
        return rgb(self.c[name]) if name in self.c else rgb(name)

    def spans(self, x, y, parts, font=None):
        for part in parts:
            text, name = part[0], part[1]
            face = {"b": self.bold, "i": self.italic}.get(part[2] if len(part) > 2 else "", font or self.font)
            self.draw.text((x, y), text, font=face, fill=self.color(name))
            x += self.draw.textlength(text, font=face)
        return x

    def window(self, box, active=False):
        x0, y0, x1, y1 = box
        overlay = Image.new("RGBA", self.image.size, (0, 0, 0, 0))
        ImageDraw.Draw(overlay).rectangle(box, fill=rgb(self.c["background"], 226))
        self.image.alpha_composite(overlay)
        border = rgb(self.c.get("hyprland_active_border", self.c["accent"])) if active else (89, 89, 89, 170)
        self.draw.rectangle((x0 - 2, y0 - 2, x1 + 2, y1 + 2), outline=border, width=2)

    def box(self, box, title, color):
        x0, y0, x1, y1 = box
        self.draw.rounded_rectangle(box, radius=4, outline=self.color(color), width=1)
        width = self.draw.textlength(title, font=self.font)
        self.draw.rectangle((x0 + 10, y0 - 7, x0 + 18 + width, y0 + 7), fill=rgb(self.c["background"]))
        self.spans(x0 + 14, y0 - 8, [(title, "bright_foreground", "b")])


def bar(cv):
    c = cv.c
    cv.draw.rectangle((0, 0, W, 24), fill=rgb(c["background"]))
    x = 14
    for index in range(1, 6):
        name = "accent" if index == 1 else "muted"
        cv.draw.text((x, 5), str(index), font=cv.font, fill=cv.color(name))
        x += 22
    clock = "Sunday 09:41"
    cv.draw.text(((W - cv.draw.textlength(clock, font=cv.font)) / 2, 5), clock, font=cv.font, fill=cv.color("foreground"))
    cv.draw.text((W - 118, 4), "      ", font=cv.font, fill=cv.color("foreground"))


def editor(cv, box):
    x0, y0, x1, y1 = box
    lh = cv.lh
    y = y0 + 12
    cv.draw.rectangle((x0 + 12, y, x0 + 52, y + lh), fill=cv.color("accent"))
    cv.spans(x0 + 16, y, [("Work", "background", "b")])
    cv.spans(x0 + 62, y, [("1:beachview", "accent"), ("  2:tide-api", "muted")])
    y += lh + 4

    tree = ["backgrounds/", "scripts/", "themes/", "  beachview/", "    colors.toml", "    icons.theme",
            "    preview.png", "    shell.lock.toml", "tests/", "CLAUDE.md", "README.md", "stow_all.sh",
            "tide.py", "tides.json", "forecast.py", "harbor.toml", "buoys.csv", "surf.lua", "shells.md",
            "sandbar.py", "lighthouse.sh", "pier.toml", "dunes.rs", "reef.go", "kelp.ts", "gulls.py",
            "boardwalk.sql", "seawall.nix", "estuary.md", "lagoon.py", "cove.rb", "jetty.c"]
    cv.spans(x0 + 12, y, [("Neo-tree", "accent", "b")])
    for i, name in enumerate(tree, start=1):
        row = y + i * lh
        if name.strip() == "colors.toml":
            cv.draw.rectangle((x0 + 12, row, x0 + 290, row + lh), fill=cv.color("selection"))
        icon, color = (" ", "blue") if name.endswith("/") else (" ", "dark_foreground")
        indent = len(name) - len(name.lstrip())
        cv.spans(x0 + 20 + indent * cv.cw, row, [(icon, color), (name.strip(), "blue" if name.endswith("/") else "foreground")])

    code = [
        [("# Predict tides for the beaches we visit.", "dark_foreground", "i")],
        [("from", "magenta"), (" dataclasses ", "foreground"), ("import", "magenta"), (" dataclass", "yellow")],
        [("from", "magenta"), (" datetime ", "foreground"), ("import", "magenta"), (" datetime, timedelta", "yellow")],
        [],
        [("PERIOD", "orange"), (" = ", "cyan"), ("timedelta", "yellow"), ("(hours=", "foreground"), ("12.42", "orange"), (")", "foreground")],
        [("BEACHES", "orange"), (" = [", "foreground"), ('"Cannon"', "green"), (", ", "foreground"), ('"Seaside"', "green"), (", ", "foreground"), ('"Manzanita"', "green"), ("]", "foreground")],
        [],
        [("@dataclass", "cyan")],
        [("class", "magenta"), (" Tide", "yellow"), (":", "foreground")],
        [("    beach", "red"), (": ", "foreground"), ("str", "yellow")],
        [("    height", "red"), (": ", "foreground"), ("float", "yellow")],
        [("    at", "red"), (": ", "foreground"), ("datetime", "yellow")],
        [],
        [("    def", "magenta"), (" is_king", "blue"), ("(", "foreground"), ("self", "red", "i"), (") -> ", "foreground"), ("bool", "yellow"), (":", "foreground")],
        [("        return", "magenta"), (" self", "red", "i"), (".height ", "foreground"), (">=", "cyan"), (" 9.5", "orange")],
        [],
        [],
        [("def", "magenta"), (" next_high", "blue"), ("(last: ", "foreground"), ("Tide", "yellow"), (") -> ", "foreground"), ("Tide", "yellow"), (":", "foreground")],
        [('    """Roll a high tide forward one period."""', "dark_foreground", "i")],
        [("    if", "magenta"), (" last ", "foreground"), ("is", "magenta"), (" None", "orange"), (":", "foreground")],
        [("        raise", "magenta"), (" ValueError", "yellow"), ("(", "foreground"), ('f"no reading for ', "green"), ("{beach}", "cyan"), ('"', "green"), (")", "foreground")],
        [("    return", "magenta"), (" Tide", "yellow"), ("(last.beach, last.height, last.at ", "foreground"), ("+", "cyan"), (" PERIOD", "orange"), (")", "foreground")],
        [],
        [],
        [("def", "magenta"), (" forecast", "blue"), ("(days: ", "foreground"), ("int", "yellow"), (" = ", "cyan"), ("7", "orange"), ("):", "foreground")],
        [("    for", "magenta"), (" beach ", "foreground"), ("in", "magenta"), (" BEACHES", "orange"), (":", "foreground")],
        [("        tide", "foreground"), (" = ", "cyan"), ("load_reading", "blue"), ("(beach)", "foreground")],
        [("        for", "magenta"), (" _ ", "foreground"), ("in", "magenta"), (" range", "cyan"), ("(days ", "foreground"), ("*", "cyan"), (" 2", "orange"), ("):", "foreground")],
        [("            tide", "foreground"), (" = ", "cyan"), ("next_high", "blue"), ("(tide)", "foreground")],
        [("            if", "magenta"), (" tide.", "foreground"), ("is_king", "blue"), ("():", "foreground")],
        [("                print", "cyan"), ("(", "foreground"), ('f"', "green"), ("{beach}", "cyan"), (': king tide at ', "green"), ("{tide.at:%a %H:%M}", "cyan"), ('"', "green"), (")", "foreground")],
        [],
        [("    # TODO: pull live buoy data instead of the cached file", "dark_foreground", "i")],
        [("    return", "magenta"), (" True", "orange")],
    ]
    cx = x0 + 312
    cv.draw.line((cx - 10, y0 + 32, cx - 10, y0 + 32 + 36 * lh), fill=cv.color("lighter_background"))
    cv.spans(cx + 30, y0 + 12, [(" tide.py", "foreground", "i"), ("  ×", "muted"), ("   forecast.py", "muted")])
    for i, line in enumerate(code):
        row = y + i * lh
        number = i + 41
        if i == 21:
            cv.draw.rectangle((cx, row, x1 - 12, row + lh), fill=cv.color("lighter_background"))
        cv.spans(cx, row, [(f"{number:>3}", "accent" if i == 21 else "muted")])
        cv.spans(cx + 40, row, line)

    status_y = y + 34 * lh + 6
    cv.draw.rectangle((x0 + 12, status_y, x1 - 12, status_y + lh + 2), fill=cv.color("lighter_background"))
    cv.draw.rectangle((x0 + 12, status_y, x0 + 76, status_y + lh + 2), fill=cv.color("blue"))
    cv.spans(x0 + 18, status_y + 1, [("NORMAL", "background", "b")])
    cv.spans(x0 + 86, status_y + 1, [(" main", "magenta"), ("  tide.py", "foreground"), ("   0   1", "yellow")])
    cv.spans(x1 - 170, status_y + 1, [("python  62:18  ", "foreground"), (" 09:41", "cyan")])

    y = status_y + lh + 16
    cv.draw.line((x0, y - 8, x1, y - 8), fill=cv.color("lighter_background"))
    cv.spans(x0 + 12, y, [("beachview ", "cyan"), ("main ", "magenta"), ("❯ ", "green"), ("ls -l", "foreground")])
    listing = [
        ("drwxr-xr-x", "-", "backgrounds", True), ("drwxr-xr-x", "-", "scripts", True),
        ("drwxr-xr-x", "-", "themes", True), ("drwxr-xr-x", "-", "tests", True),
        (".rw-r--r--", "2.1k", "CLAUDE.md", False), (".rw-r--r--", "1.4k", "README.md", False),
        (".rwxr-xr-x", "9.8k", "stow_all.sh", False), (".rw-r--r--", "3.2k", "tide.py", False),
        (".rw-r--r--", "58k", "tides.json", False), (".rw-r--r--", "612", "harbor.toml", False),
        (".rw-r--r--", "44k", "buoys.csv", False), (".rwxr-xr-x", "1.1k", "lighthouse.sh", False),
        (".rw-r--r--", "830", "shells.md", False), (".rw-r--r--", "2.7k", "sandbar.py", False),
        (".rw-r--r--", "1.9k", "pier.toml", False), (".rw-r--r--", "4.6k", "reef.go", False),
    ]
    y += lh
    cv.spans(x0 + 12, y, [("Permissions Size User  Date Modified Name", "foreground", "b")])
    for perms, size, name, is_dir in listing:
        y += lh
        parts = []
        for ch in perms:
            parts.append((ch, {"d": "blue", "r": "yellow", "w": "red", "x": "green"}.get(ch, "muted")))
        parts += [(f"{size:>6} ", "green" if size != "-" else "muted"), ("david ", "yellow"),
                  ("27 Sep 09:12 ", "blue"),
                  ((" " if is_dir else " ") + name,
                   "blue" if is_dir else ("green" if perms[3] == "x" else "foreground"))]
        cv.spans(x0 + 12, y, parts)
    y += lh + 6
    cv.spans(x0 + 12, y, [("beachview ", "cyan"), ("main ", "magenta"), ("❯ ", "green")])


def btop(cv, box):
    x0, y0, x1, y1 = box
    rng = random.Random(7)
    lh = cv.lh
    cpu = (x0 + 14, y0 + 16, x1 - 14, y0 + 212)
    cv.box(cpu, "¹cpu", "magenta")
    cv.draw.rectangle((x1 - 204, y0 + 8, x1 - 30, y0 + 24), fill=rgb(cv.c["background"]))
    cv.spans(x1 - 196, y0 + 8, [("09:41:07", "bright_foreground"), ("   2000ms", "muted")])
    gx0, gx1, gy1 = cpu[0] + 8, cpu[0] + 330, cpu[3] - 42
    steps = ["cyan", "blue", "magenta"]
    for i, x in enumerate(range(int(gx0), int(gx1), 4)):
        height = 18 + abs(rng.gauss(0, 32)) + 30 * (1 + math.sin(i / 9))
        for dy in range(0, int(height), 4):
            level = min(2, int(dy / 40))
            cv.draw.text((x, gy1 - dy), "⣿" if dy < height - 4 else "⡀", font=cv.font, fill=cv.color(steps[level]))
    cv.spans(cpu[0] + 10, cpu[3] - 20, [("up 3d 04:12", "light_foreground")])
    cores = cpu[0] + 360
    cv.spans(cores, cpu[1] + 12, [("CPU ", "foreground", "b"), ("■" * 22, "cyan"), ("  18%", "foreground"), ("  52°C", "yellow")])
    for i in range(16):
        col, row = divmod(i, 8)
        value = rng.randint(1, 38)
        tx, ty = cores + col * 196, cpu[1] + 32 + row * lh
        bar_color = "cyan" if value < 15 else "blue" if value < 30 else "magenta"
        cv.spans(tx, ty, [(f"C{i:<2} ", "foreground"), ("■" * max(1, value // 5), bar_color),
                          (f"{value:>4}%", "foreground")])
    cv.spans(cores, cpu[3] - 20, [("Load avg: ", "foreground"), ("0.82 0.91 0.77", "light_foreground")])

    mem = (x0 + 14, y0 + 230, x0 + 380, y1 - 14)
    cv.box(mem, "²mem", "green")
    y = mem[1] + 12
    for label, value, pct, start, end in [
        ("Used", "18.4 GiB", 30, "green", "cyan"), ("Available", "43.7 GiB", 70, "yellow", "red"),
        ("Cached", "21.2 GiB", 34, "blue", "cyan"), ("Free", "22.5 GiB", 36, "magenta", "blue"),
    ]:
        cv.spans(mem[0] + 10, y, [(f"{label}:", "foreground"), (f"{value:>{28 - len(label)}}", "bright_foreground")])
        y += lh
        filled = int(pct / 100 * 34)
        for k in range(34):
            color = mix(cv.c[start], cv.c[end], k / 33) if k < filled else rgb(cv.c["selection"])
            cv.draw.text((mem[0] + 10 + k * cv.cw, y), "■", font=cv.font, fill=color)
        cv.spans(mem[0] + 10 + 35 * cv.cw, y, [(f"{pct}%", "foreground")])
        y += lh + 8
    net = (x0 + 14, y + 6, x0 + 380, y1 - 14)
    cv.box(net, "³net", "red")
    for k, x in enumerate(range(int(net[0]) + 10, int(net[2]) - 10, 4)):
        up = abs(rng.gauss(0, 18)) + 6
        cv.draw.line((x, net[3] - 30, x, net[3] - 30 - up), fill=mix(cv.c["green"], cv.c["blue"], min(1, up / 50)), width=2)
        down = abs(rng.gauss(0, 14)) + 4
        cv.draw.line((x, net[1] + 44, x, net[1] + 44 - min(30, down)), fill=mix(cv.c["yellow"], cv.c["red"], min(1, down / 30)), width=2)
    cv.spans(net[0] + 10, net[1] + 50, [("▼ 1.8 MiB/s", "yellow"), ("   ▲ 240 KiB/s", "green")])

    proc = (x0 + 394, y0 + 230, x1 - 14, y1 - 14)
    cv.box(proc, "⁴proc", "accent")
    rows = [("21873", "nvim", "nvim tide.py", "412M", 6.1), ("20914", "ghostty", "/usr/bin/ghostty", "288M", 3.4),
            ("1204", "Hyprland", "Hyprland", "231M", 2.2), ("19230", "chrome", "/opt/google/chrome", "1.1G", 1.9),
            ("20411", "herdr", "herdr", "96M", 1.2), ("1311", "quickshell", "omarchy-shell", "184M", 0.9),
            ("18842", "btop", "btop", "12M", 0.7), ("20007", "pipewire", "/usr/bin/pipewire", "31M", 0.4),
            ("20009", "wireplumber", "/usr/bin/wireplumber", "45M", 0.3), ("19888", "python3", "python3 tide.py", "64M", 0.3),
            ("1402", "mako", "mako", "18M", 0.1), ("11020", "yazi", "yazi", "40M", 0.1),
            ("1502", "hypridle", "hypridle", "9M", 0.0), ("1422", "spotify", "/opt/spotify", "590M", 0.0),
            ("19201", "code", "/opt/visual-studio", "610M", 0.0), ("1505", "voxtype", "voxtype", "72M", 0.0),
            ("1330", "sshd", "sshd: david", "8M", 0.0), ("20090", "zsh", "-bash", "6M", 0.0),
            ("21002", "git", "git fetch", "11M", 0.0), ("1601", "hyprsunset", "hyprsunset", "7M", 0.0),
            ("20101", "gvfsd", "/usr/lib/gvfsd", "9M", 0.0), ("1709", "xdg-portal", "xdg-desktop-portal", "21M", 0.0),
            ("1711", "tailscaled", "tailscaled", "52M", 0.0), ("2005", "mpv", "mpv --idle", "36M", 0.0)]
    y = proc[1] + 12
    cv.spans(proc[0] + 10, y, [("  Pid: Program:     Command:              MemB   Cpu%", "foreground", "b")])
    for i, (pid, prog, cmd, memb, pct) in enumerate(rows):
        y += lh
        if y + lh > proc[3] - 22:
            break
        if i == 0:
            cv.draw.rectangle((proc[0] + 4, y, proc[2] - 4, y + lh), fill=cv.color("selection"))
        shade = mix(cv.c["cyan"], cv.c["magenta"], min(1, pct / 6))
        cv.spans(proc[0] + 10, y, [(f"{pid:>6} ", "light_foreground"), (f"{prog:<12}", "accent" if i == 0 else "foreground"),
                                   (f"{cmd[:21]:<22}", "dark_foreground"), (f"{memb:>5} ", "light_foreground")])
        cv.draw.text((proc[2] - 60, y), f"{pct:>4.1f}", font=cv.font, fill=shade)
    cv.spans(proc[0] + 10, proc[3] - 18, [("↑ select ↓ ", "accent"), ("info  terminate  kill  signals", "muted")])


def files(cv, box, icons):
    x0, y0, x1, y1 = box
    c = cv.c
    cv.draw.rectangle((x0, y0, x0 + 170, y1), fill=rgb(c["dark_background"], 255))
    cv.draw.text((x0 + 16, y0 + 14), "", font=cv.glyphs, fill=cv.color("foreground"))
    cv.draw.text((x0 + 66, y0 + 13), "Files", font=cv.ui_bold, fill=cv.color("bright_foreground"))
    for i, (glyph, label) in enumerate([("", "Home"), ("", "Recent"), ("", "Starred"),
                                        ("", "Network"), ("", "Trash"), ("", "Downloads"),
                                        ("", "Pictures")]):
        y = y0 + 54 + i * 34 + (10 if i >= 5 else 0)
        if i == 0:
            cv.draw.rounded_rectangle((x0 + 8, y - 6, x0 + 162, y + 24), radius=6, fill=cv.color("selection"))
        cv.draw.text((x0 + 20, y), glyph, font=cv.glyphs, fill=cv.color("foreground"))
        cv.draw.text((x0 + 44, y), label, font=cv.ui, fill=cv.color("foreground"))
    cv.draw.rounded_rectangle((x0 + 250, y0 + 10, x1 - 150, y0 + 38), radius=6, fill=cv.color("lighter_background"))
    cv.draw.text((x0 + 262, y0 + 14), "", font=cv.glyphs, fill=cv.color("bright_foreground"))
    cv.draw.text((x0 + 286, y0 + 13), "Home", font=cv.ui_bold, fill=cv.color("bright_foreground"))
    cv.draw.text((x0 + 196, y0 + 14), "   ", font=cv.glyphs, fill=cv.color("muted"))
    names = [("folder", "Desktop"), ("folder-documents", "Documents"), ("folder-download", "Downloads"),
             ("folder-dropbox", "Dropbox"), ("folder-music", "Music"), ("folder-pictures", "Pictures"),
             ("folder-publicshare", "Public"), ("folder-videos", "Videos")]
    area = x1 - (x0 + 170)
    step = area / 4
    for i, (icon, label) in enumerate(names):
        col, row = i % 4, i // 4
        cx = x0 + 170 + step * col + step / 2
        top = y0 + 60 + row * 140
        image = Image.open(icons / f"{icon}.png").convert("RGBA").resize((88, 88), Image.LANCZOS)
        cv.image.alpha_composite(image, (int(cx - 44), int(top)))
        width = cv.draw.textlength(label, font=cv.ui)
        cv.draw.text((cx - width / 2, top + 96), label, font=cv.ui, fill=cv.color("foreground"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--theme", type=Path, default=ROOT / "themes/beachview")
    parser.add_argument("--wallpaper", type=Path)
    args = parser.parse_args()

    colors = tomllib.loads((args.theme / "colors.toml").read_text())
    if args.wallpaper is None:
        manifest = json.loads((ROOT / "backgrounds/manifest.json").read_text())
        args.wallpaper = ROOT / "backgrounds" / manifest["selected"]
    icon_theme = (args.theme / "icons.theme").read_text().strip()
    icons = Path("/usr/share/icons") / icon_theme / "256x256/places"

    wallpaper = Image.open(args.wallpaper).convert("RGB")
    scale = max(W / wallpaper.width, H / wallpaper.height)
    wallpaper = wallpaper.resize((round(wallpaper.width * scale), round(wallpaper.height * scale)), Image.LANCZOS)
    left, top = (wallpaper.width - W) // 2, (wallpaper.height - H) // 2
    image = wallpaper.crop((left, top, left + W, top + H)).convert("RGBA")

    cv = Canvas(image, colors)
    bar(cv)
    gap, top = 10, 34
    left_box = (gap, top, 898, H - gap)
    btop_box = (910, top, W - gap, 660)
    files_box = (910, 672, W - gap, H - gap)
    for box, active in ((btop_box, False), (files_box, False), (left_box, True)):
        cv.window(box, active)
    editor(cv, left_box)
    btop(cv, btop_box)
    files(cv, files_box, icons)

    out = args.theme / "preview.png"
    image.convert("RGB").quantize(256, method=Image.Quantize.MEDIANCUT).save(out, optimize=True)
    print(f"Wrote {out}")


if __name__ == "__main__":
    main()
