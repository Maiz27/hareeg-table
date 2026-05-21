from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter


def smoothstep(edge0: float, edge1: float, value: np.ndarray) -> np.ndarray:
    x = np.clip((value - edge0) / (edge1 - edge0), 0.0, 1.0)
    return x * x * (3.0 - 2.0 * x)


def checker_background_model(rgb: np.ndarray) -> np.ndarray:
    gray = rgb.mean(axis=2)
    light = np.array([254.0, 254.0, 254.0], dtype=np.float32)
    dark = np.array([242.0, 242.0, 242.0], dtype=np.float32)
    return np.where((gray[..., None] >= 248.0), light, dark)


def extract_alpha(rgb: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    rgbf = rgb.astype(np.float32)
    bg = checker_background_model(rgbf)

    distance = np.linalg.norm(rgbf - bg, axis=2)
    max_channel = rgbf.max(axis=2)
    min_channel = rgbf.min(axis=2)
    chroma = max_channel - min_channel

    alpha_from_distance = smoothstep(14.0, 42.0, distance)
    alpha_from_chroma = smoothstep(7.0, 18.0, chroma)
    alpha = np.maximum(alpha_from_distance, alpha_from_chroma)

    # Keep real light ivory/gold artwork opaque while the neutral checker drops
    # away. This protects the suit medallion interiors from being punched out.
    warm_delta = rgbf[..., 0] - rgbf[..., 2]
    warm_light_art = (max_channel > 205.0) & (warm_delta > 18.0)
    alpha = np.where(warm_light_art, np.maximum(alpha, 0.96), alpha)

    # Remove faint checker anti-aliasing and keep artwork edges soft.
    alpha = np.where(alpha < 0.035, 0.0, alpha)
    alpha_image = Image.fromarray((alpha * 255.0).astype(np.uint8), mode="L")
    alpha_image = alpha_image.filter(ImageFilter.GaussianBlur(radius=0.35))
    alpha = np.asarray(alpha_image).astype(np.float32) / 255.0

    return alpha, bg


def decontaminate(rgb: np.ndarray, alpha: np.ndarray, bg: np.ndarray) -> np.ndarray:
    rgbf = rgb.astype(np.float32)
    alpha3 = np.clip(alpha[..., None], 0.08, 1.0)
    clean = (rgbf - ((1.0 - alpha3) * bg)) / alpha3
    clean = np.clip(clean, 0.0, 255.0)
    clean[alpha < 0.01] = 0.0
    return clean.astype(np.uint8)


def bbox_from_alpha(alpha: np.ndarray) -> tuple[int, int, int, int]:
    ys, xs = np.where(alpha > 0.08)
    if len(xs) == 0 or len(ys) == 0:
        raise ValueError("No foreground detected")
    left, right = xs.min(), xs.max() + 1
    top, bottom = ys.min(), ys.max() + 1
    pad = 8
    return (
        max(left - pad, 0),
        max(top - pad, 0),
        min(right + pad, alpha.shape[1]),
        min(bottom + pad, alpha.shape[0]),
    )


def make_foreground(source: Path, size: int, mark_size: int) -> Image.Image:
    image = Image.open(source).convert("RGB")
    rgb = np.asarray(image)
    alpha, bg = extract_alpha(rgb)
    clean_rgb = decontaminate(rgb, alpha, bg)
    rgba = np.dstack([clean_rgb, (alpha * 255.0).astype(np.uint8)])
    extracted = Image.fromarray(rgba, mode="RGBA")

    bbox = bbox_from_alpha(alpha)
    cropped = extracted.crop(bbox)
    scale = mark_size / max(cropped.width, cropped.height)
    resized = cropped.resize(
        (round(cropped.width * scale), round(cropped.height * scale)),
        Image.Resampling.LANCZOS,
    )

    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    offset = ((size - resized.width) // 2, (size - resized.height) // 2)
    canvas.alpha_composite(resized, offset)
    return canvas


def make_background(size: int) -> Image.Image:
    y, x = np.mgrid[0:size, 0:size].astype(np.float32)
    nx = (x / (size - 1)) - 0.5
    ny = (y / (size - 1)) - 0.5
    radius = np.sqrt((nx * 1.05) ** 2 + (ny * 1.05) ** 2)
    center = np.array([18, 56, 47], dtype=np.float32)
    edge = np.array([21, 17, 14], dtype=np.float32)
    t = smoothstep(0.12, 0.72, radius)[..., None]
    base = (center * (1.0 - t)) + (edge * t)

    rng = np.random.default_rng(7426)
    noise = rng.normal(0, 4.2, (size, size, 1)).astype(np.float32)
    grain = rng.normal(0, 1.1, (size, size, 3)).astype(np.float32)
    pixels = np.clip(base + noise + grain, 0, 255).astype(np.uint8)
    image = Image.fromarray(pixels, mode="RGB").filter(
        ImageFilter.GaussianBlur(radius=0.25)
    )

    return image


def rounded_mask(size: int, radius: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, size - 1, size - 1],
        radius=radius,
        fill=255,
    )
    return mask


def circle_mask(size: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, size - 1, size - 1], fill=255)
    return mask


def make_preview(foreground: Image.Image, background: Image.Image, out: Path) -> None:
    composite = background.convert("RGBA")
    composite.alpha_composite(foreground)

    masks = [
        rounded_mask(composite.width, round(composite.width * 0.22)),
        rounded_mask(composite.width, round(composite.width * 0.34)),
        circle_mask(composite.width),
    ]

    previews = []
    for mask in masks:
        tile = Image.new("RGBA", composite.size, (21, 17, 14, 255))
        tile.paste(composite, (0, 0), mask)
        previews.append(tile.resize((384, 384), Image.Resampling.LANCZOS))

    gutter = 32
    sheet = Image.new(
        "RGBA",
        ((384 * len(previews)) + (gutter * (len(previews) + 1)), 384 + (gutter * 2)),
        (21, 17, 14, 255),
    )
    for i, preview in enumerate(previews):
        sheet.alpha_composite(preview, (gutter + i * (384 + gutter), gutter))
    sheet.save(out)


def make_monochrome(foreground: Image.Image) -> Image.Image:
    alpha = foreground.getchannel("A")
    monochrome = Image.new("RGBA", foreground.size, (255, 255, 255, 0))
    monochrome.putalpha(alpha)
    return monochrome


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("--out-dir", type=Path, default=Path("assets/brand/launcher"))
    parser.add_argument("--size", type=int, default=1024)
    parser.add_argument("--mark-size", type=int, default=640)
    args = parser.parse_args()

    args.out_dir.mkdir(parents=True, exist_ok=True)
    foreground = make_foreground(args.source, args.size, args.mark_size)
    background = make_background(args.size)
    composite = background.convert("RGBA")
    composite.alpha_composite(foreground)

    foreground.save(args.out_dir / "sandline_joker_foreground.png")
    background.save(args.out_dir / "sandline_joker_background.png")
    composite.save(args.out_dir / "sandline_joker_composite.png")
    make_monochrome(foreground).save(args.out_dir / "sandline_joker_monochrome.png")
    make_preview(foreground, background, args.out_dir / "sandline_joker_mask_preview.png")


if __name__ == "__main__":
    main()
