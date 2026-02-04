#!/usr/bin/env python3

"""Helpers for generating flamegraph artifacts under prof/."""

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path


def require_command(name: str) -> None:
    if shutil.which(name) is None:
        sys.exit(f"Missing required command: {name}")


def run(cmd, **kwargs) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, check=True, **kwargs)


def generate_svg(folded_path: Path) -> Path:
    svg_path = folded_path.with_suffix(".svg")
    with open(svg_path, "wb") as handle:
        run(["flamegraph", folded_path.name], cwd=folded_path.parent, stdout=handle)
    return svg_path


def generate_png(folded_path: Path) -> Path:
    png_path = folded_path.with_suffix(".png")
    gprof = subprocess.Popen(
        ["gprof2dot", "-f", "collapse", folded_path.name],
        cwd=folded_path.parent,
        stdout=subprocess.PIPE,
    )
    try:
        with open(png_path, "wb") as handle:
            dot = subprocess.Popen(
                ["dot", "-Tpng", "-o", png_path.name],
                cwd=folded_path.parent,
                stdin=gprof.stdout,
            )
            if gprof.stdout:
                gprof.stdout.close()
            dot.communicate()
            if dot.returncode != 0:
                raise subprocess.CalledProcessError(dot.returncode, dot.args)
    finally:
        gprof_rc = gprof.wait()
    if gprof_rc != 0:
        raise subprocess.CalledProcessError(gprof_rc, gprof.args)
    return png_path


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Generate flamegraph artifacts from prof-* scripts")
    parser.add_argument("target", help="Profiler target name (e.g. scene -> prof-scene)")
    parser.add_argument(
        "--fnl",
        default="build/space",
        help="Path to the space runner (default: build/space)",
    )
    parser.add_argument(
        "--top",
        type=int,
        default=10,
        help="Number of stacks/frames to show in the textual summary (default: 10)",
    )
    parser.add_argument(
        "--no-summary",
        action="store_true",
        help="Skip printing the folded file summary",
    )
    parser.add_argument(
        "--skip-images",
        action="store_true",
        help="Skip generating SVG/PNG artifacts (still runs profiler and summary)",
    )
    return parser


def parse_folded(path: Path):
    stacks = []
    leaves = {}
    total = 0
    with open(path, "r", encoding="utf-8") as handle:
        for raw in handle:
            line = raw.strip()
            if not line:
                continue
            try:
                stack, samples_text = line.rsplit(" ", 1)
                samples = int(samples_text)
            except ValueError:
                continue
            total += samples
            stacks.append((stack, samples))
            leaf = stack.split(";")[-1]
            leaves[leaf] = leaves.get(leaf, 0) + samples
    return total, stacks, leaves


def format_percent(samples: int, total: int) -> str:
    if total <= 0:
        return "0.0%"
    return f"{(samples / total) * 100:.1f}%"


def summarize_folded(path: Path, limit: int) -> None:
    total, stacks, leaves = parse_folded(path)
    if total == 0:
        print("No samples recorded; nothing to summarize.")
        return
    stacks.sort(key=lambda item: item[1], reverse=True)
    leaves_items = sorted(leaves.items(), key=lambda item: item[1], reverse=True)

    print("\nSummary ({} samples)".format(total))
    print("Top stacks:")
    for idx, (stack, samples) in enumerate(stacks[:limit], start=1):
        print(f"  {idx:>2}. {format_percent(samples, total):>6} ({samples:>8})  {stack}")

    print("Top leaf frames:")
    for idx, (leaf, samples) in enumerate(leaves_items[:limit], start=1):
        print(f"  {idx:>2}. {format_percent(samples, total):>6} ({samples:>8})  {leaf}")


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()
    target = args.target.strip()
    if not target:
        parser.error("target must not be empty")

    repo_root = Path(__file__).resolve().parents[1]
    fnl_runner = repo_root / args.fnl
    if not fnl_runner.exists():
        sys.exit(f"Missing space runner at {fnl_runner}. Build the project first (make build).")

    if not args.skip_images:
        require_command("flamegraph")
        require_command("gprof2dot")
        require_command("dot")

    prof_dir = repo_root / "prof"
    prof_dir.mkdir(parents=True, exist_ok=True)

    folded_path = prof_dir / f"{target}.folded"
    env = os.environ.copy()
    env["SPACE_FENNEL_FLAMEGRAPH"] = str(folded_path)

    profiler_script = f"prof-{target}"
    print(f"Running {profiler_script} -> {folded_path.relative_to(repo_root)}")
    run([str(fnl_runner), "-m", profiler_script], cwd=repo_root, env=env)

    if not folded_path.exists():
        sys.exit(f"Expected folded file at {folded_path}, but it was not created.")

    if args.skip_images:
        svg_path = png_path = None
    else:
        print("Generating flamegraph SVG...")
        svg_path = generate_svg(folded_path)

        print("Generating call graph PNG...")
        png_path = generate_png(folded_path)

    rel_folded = folded_path.relative_to(repo_root)
    print(f"Wrote {rel_folded}")
    if svg_path:
        print(f"Wrote {svg_path.relative_to(repo_root)}")
    if png_path:
        print(f"Wrote {png_path.relative_to(repo_root)}")

    if not args.no_summary:
        summarize_folded(folded_path, args.top)


if __name__ == "__main__":
    main()
