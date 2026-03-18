#!/usr/bin/env python3
import argparse
from pathlib import Path

from PIL import Image


ICON_SIZES = [(256, 256), (128, 128), (64, 64), (48, 48), (32, 32), (24, 24), (16, 16)]


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate a Windows .ico from a PNG source.")
    parser.add_argument("--input", required=True, help="Source PNG path")
    parser.add_argument("--output", required=True, help="Destination .ico path")
    args = parser.parse_args()

    input_path = Path(args.input)
    output_path = Path(args.output)

    if not input_path.is_file():
        raise SystemExit(f"Missing input PNG: {input_path}")

    output_path.parent.mkdir(parents=True, exist_ok=True)

    with Image.open(input_path) as source_image:
        image = source_image.convert("RGBA")
        width, height = image.size
        if width != height:
            raise SystemExit(f"Expected square icon source, got {width}x{height}: {input_path}")
        if width < 256:
            raise SystemExit(f"Expected icon source at least 256x256, got {width}x{height}: {input_path}")

        image.save(output_path, format="ICO", sizes=ICON_SIZES)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
