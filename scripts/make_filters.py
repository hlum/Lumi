#!/usr/bin/env python3
"""Generates the self-made filter pack: one .cube per look plus catalog.json. Re-run to regenerate; output is deterministic."""
import json, os

OUT = os.path.join(os.path.dirname(__file__), "..", "Lumi", "Resources", "Content", "Filters")
SIZE = 16

def clamp(v): return 0.0 if v < 0 else 1.0 if v > 1 else v

def grade(r, g, b, p):
    # temperature/tint
    r += p.get("temp", 0) * 0.12; b -= p.get("temp", 0) * 0.12; g += p.get("tint", 0) * 0.08
    # exposure
    k = 2 ** p.get("exp", 0); r, g, b = r * k, g * k, b * k
    # contrast about mid gray
    c = 1 + p.get("contrast", 0)
    r, g, b = (r - .5) * c + .5, (g - .5) * c + .5, (b - .5) * c + .5
    # saturation
    y = 0.2126 * r + 0.7152 * g + 0.0722 * b; s = 1 + p.get("sat", 0)
    r, g, b = y + (r - y) * s, y + (g - y) * s, y + (b - y) * s
    # fade (lift blacks) and crush
    f = p.get("fade", 0); r, g, b = r * (1 - f) + f, g * (1 - f) + f, b * (1 - f) + f
    # split tone: shadows toward (sr,sg,sb), highlights toward (hr,hg,hb)
    y = 0.2126 * r + 0.7152 * g + 0.0722 * b
    for (key, w) in (("shadow", 1 - y), ("high", y)):
        t = p.get(key)
        if t:
            a = 0.18 * w * w
            r, g, b = r + (t[0] - r) * a, g + (t[1] - g) * a, b + (t[2] - b) * a
    # gamma
    gm = p.get("gamma", 1.0); r, g, b = (clamp(x) ** (1 / gm) for x in (r, g, b))
    # channel multipliers
    cm = p.get("rgb", (1, 1, 1)); r, g, b = r * cm[0], g * cm[1], b * cm[2]
    if p.get("mono"):
        y = clamp(0.2126 * r + 0.7152 * g + 0.0722 * b); r = g = b = y
    return clamp(r), clamp(g), clamp(b)

TEAL = (0.1, 0.45, 0.5); ORANGE = (1.0, 0.65, 0.3); PINK = (1.0, 0.7, 0.8); BLUE = (0.2, 0.3, 0.7); GREEN = (0.3, 0.6, 0.4); CREAM = (1.0, 0.95, 0.8)

# (id, English, Japanese, category, params)
LOOKS = [
 # basics
 ("clean", "Clean", "クリーン", "basics", dict(contrast=.08, sat=.08)),
 ("bright", "Bright", "ブライト", "basics", dict(exp=.35, contrast=.05)),
 ("deep", "Deep", "ディープ", "basics", dict(exp=-.2, contrast=.2, sat=.1)),
 ("soft", "Soft", "ソフト", "basics", dict(contrast=-.15, fade=.05, sat=-.05)),
 ("vivid", "Vivid", "ビビッド", "basics", dict(contrast=.15, sat=.4)),
 ("mono", "Mono", "モノ", "basics", dict(contrast=.2, mono=True)),
 ("warm", "Warm", "ウォーム", "basics", dict(temp=.6)),
 ("cool", "Cool", "クール", "basics", dict(temp=-.6)),
 # flash / digicam / CCD
 ("flash", "Flash", "フラッシュ", "flash", dict(exp=.3, contrast=.25, sat=.1, fade=.02, high=(1, 1, 1))),
 ("flash-night", "Night flash", "ナイトフラッシュ", "flash", dict(exp=.1, contrast=.35, sat=.15, shadow=BLUE)),
 ("ccd-2005", "CCD 2005", "CCD 2005", "flash", dict(contrast=.2, sat=.25, temp=-.1, tint=.1, fade=.03)),
 ("digicam", "Digicam", "デジカメ", "flash", dict(contrast=.3, sat=.3, exp=.15, rgb=(1.02, 1, .96))),
 ("compact", "Compact", "コンパクト", "flash", dict(contrast=.22, sat=.12, temp=.15, exp=.1)),
 ("y2k", "Y2K", "Y2K", "flash", dict(contrast=.3, sat=.35, temp=-.2, high=PINK)),
 ("point-and-shoot", "Point & shoot", "ポイントシュート", "flash", dict(contrast=.25, exp=.2, temp=.1, fade=.02)),
 # film
 ("film-gold", "Gold 200", "ゴールド200", "film", dict(temp=.4, sat=.1, fade=.05, contrast=.1, shadow=ORANGE)),
 ("film-fuji", "Green film", "グリーンフィルム", "film", dict(tint=.25, sat=.05, fade=.06, contrast=.12, shadow=GREEN)),
 ("film-portra", "Portra", "ポートラ", "film", dict(temp=.2, sat=-.05, contrast=-.05, fade=.05, high=CREAM)),
 ("film-ektar", "Ektar", "エクター", "film", dict(sat=.45, contrast=.2, temp=.1)),
 ("film-bw", "B&W film", "白黒フィルム", "film", dict(mono=True, contrast=.3, fade=.04)),
 ("film-faded", "Faded film", "色あせフィルム", "film", dict(fade=.14, sat=-.2, contrast=-.1, temp=.15)),
 ("film-cross", "Cross process", "クロスプロセス", "film", dict(contrast=.3, sat=.2, rgb=(1.05, 1, .9), shadow=TEAL)),
 ("film-tungsten", "Tungsten", "タングステン", "film", dict(temp=-.5, contrast=.15, sat=.05)),
 ("film-expired", "Expired", "期限切れ", "film", dict(fade=.1, tint=.2, temp=.3, sat=-.1, shadow=PINK)),
 # camera simulation
 ("cam-instant", "Instant", "インスタント", "camera", dict(fade=.1, contrast=-.05, temp=.25, sat=.05, high=CREAM)),
 ("cam-polaroid", "Polaroid", "ポラロイド", "camera", dict(fade=.08, tint=.1, temp=.2, contrast=.05, shadow=TEAL)),
 ("cam-lomo", "Lomo", "ロモ", "camera", dict(contrast=.4, sat=.3, gamma=1.1, shadow=BLUE)),
 ("cam-toy", "Toy camera", "トイカメラ", "camera", dict(contrast=.3, sat=.25, rgb=(1.04, 1, 1.03), fade=.04)),
 ("cam-disposable", "Disposable", "使い捨て", "camera", dict(exp=.2, contrast=.25, sat=.2, temp=.2)),
 ("cam-rangefinder", "Rangefinder", "レンジファインダー", "camera", dict(contrast=.18, sat=-.05, fade=.03)),
 ("cam-medium", "Medium format", "中判", "camera", dict(contrast=.1, sat=.08, gamma=1.05)),
 ("cam-vhs", "VHS", "VHS", "camera", dict(fade=.1, sat=-.15, contrast=-.1, tint=-.1, shadow=BLUE, high=PINK)),
 # Japanese
 ("jp-clear", "Clear air", "透明感", "japanese", dict(exp=.3, contrast=-.12, sat=-.1, temp=-.15, fade=.04)),
 ("jp-airy", "Airy", "エアリー", "japanese", dict(exp=.4, contrast=-.2, sat=-.15, fade=.06, high=(1, 1, 1))),
 ("jp-sakura", "Sakura", "さくら", "japanese", dict(exp=.2, tint=.2, temp=.1, sat=-.05, fade=.05, high=PINK)),
 ("jp-umi", "Sea breeze", "海風", "japanese", dict(exp=.25, temp=-.3, sat=.05, contrast=-.08, shadow=TEAL)),
 ("jp-kissaten", "Kissaten", "喫茶店", "japanese", dict(temp=.45, contrast=.1, sat=-.1, fade=.06, shadow=ORANGE)),
 ("jp-showa", "Showa", "昭和", "japanese", dict(temp=.35, fade=.12, sat=-.2, contrast=-.05)),
 ("jp-natural", "Natural light", "自然光", "japanese", dict(exp=.15, contrast=-.05, sat=-.05)),
 ("jp-milk", "Milk tea", "ミルクティー", "japanese", dict(temp=.3, exp=.2, sat=-.2, contrast=-.12, fade=.07, high=CREAM)),
 # cinematic
 ("cine-teal-orange", "Teal & orange", "ティール＆オレンジ", "cinema", dict(contrast=.2, sat=.1, shadow=TEAL, high=ORANGE)),
 ("cine-noir", "Noir", "ノワール", "cinema", dict(mono=True, contrast=.45, exp=-.15)),
 ("cine-blockbuster", "Blockbuster", "ブロックバスター", "cinema", dict(contrast=.3, sat=.05, temp=-.1, shadow=BLUE)),
 ("cine-western", "Western", "西部劇", "cinema", dict(temp=.5, contrast=.2, sat=-.1, shadow=ORANGE)),
 ("cine-moody", "Moody", "ムーディー", "cinema", dict(exp=-.3, contrast=.2, sat=-.15, shadow=BLUE)),
 ("cine-dream", "Dream", "ドリーム", "cinema", dict(exp=.2, fade=.1, sat=.1, contrast=-.15, high=PINK, shadow=BLUE)),
 ("cine-scifi", "Sci-fi", "SF", "cinema", dict(temp=-.4, contrast=.3, sat=.1, shadow=TEAL)),
 ("cine-war", "Desaturated", "ミュート", "cinema", dict(sat=-.5, contrast=.3, exp=-.1)),
 ("cine-night-city", "Night city", "夜の街", "cinema", dict(exp=-.1, contrast=.35, sat=.2, shadow=BLUE, high=PINK)),
 # Chinese color tones
 ("cn-cream", "Cream skin", "クリーム肌", "chinese", dict(exp=.3, temp=.15, sat=-.12, contrast=-.1, high=CREAM)),
 ("cn-milk-white", "Milk white", "ミルクホワイト", "chinese", dict(exp=.4, contrast=-.15, sat=-.2, fade=.05)),
 ("cn-ink", "Ink", "水墨", "chinese", dict(mono=True, contrast=.35, fade=.06)),
 ("cn-peach", "Peach", "ピーチ", "chinese", dict(exp=.2, tint=.2, temp=.2, sat=.05, high=PINK)),
 ("cn-matcha", "Matcha", "抹茶", "chinese", dict(tint=.3, temp=-.05, sat=-.1, fade=.05, shadow=GREEN)),
 ("cn-jade", "Jade", "翡翠", "chinese", dict(tint=.25, temp=-.2, sat=.1, shadow=TEAL)),
 ("cn-red-gold", "Red gold", "紅金", "chinese", dict(temp=.4, sat=.3, contrast=.2, shadow=(0.6, 0.1, 0.1))),
 ("cn-misty", "Misty", "霧", "chinese", dict(exp=.2, contrast=-.25, sat=-.2, fade=.12)),
 ("cn-retro-hk", "Retro HK", "香港レトロ", "chinese", dict(contrast=.3, sat=.2, tint=.15, shadow=TEAL, high=(1, .8, .5))),
 # skin / portrait
 ("pt-glow", "Glow", "グロウ", "portrait", dict(exp=.25, contrast=-.08, temp=.1, sat=-.02, high=PINK)),
 ("pt-rosy", "Rosy", "ローズ", "portrait", dict(tint=.15, temp=.15, sat=.05, high=PINK)),
 ("pt-porcelain", "Porcelain", "磁器肌", "portrait", dict(exp=.35, contrast=-.12, sat=-.15)),
 ("pt-sun-kissed", "Sun-kissed", "日焼け", "portrait", dict(temp=.4, sat=.12, contrast=.08, exp=.05)),
]

def cube(params):
    lines = [f"TITLE \"Lumi\"", f"LUT_3D_SIZE {SIZE}"]
    d = SIZE - 1
    for bi in range(SIZE):
        for gi in range(SIZE):
            for ri in range(SIZE):
                r, g, b = grade(ri / d, gi / d, bi / d, params)
                lines.append(f"{r:.5f} {g:.5f} {b:.5f}")
    return "\n".join(lines) + "\n"

def main():
    os.makedirs(OUT, exist_ok=True)
    catalog = []
    for (id_, en, ja, cat, p) in LOOKS:
        fn = f"{id_}.cube"
        with open(os.path.join(OUT, fn), "w") as f: f.write(cube(p))
        catalog.append({"id": id_, "file": fn, "name": en, "nameJa": ja, "category": cat})
    with open(os.path.join(OUT, "catalog.json"), "w") as f: json.dump(catalog, f, ensure_ascii=False, indent=1)
    print(len(catalog), "filters")

if __name__ == "__main__": main()
