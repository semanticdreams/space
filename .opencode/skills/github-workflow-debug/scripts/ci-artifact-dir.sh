#!/usr/bin/env bash
# Ensure .superpowers/sdd/ exists with a self-ignoring .gitignore so CI
# review artifacts (diffs, review packages) are never staged or committed.
set -euo pipefail

root=$(git rev-parse --show-toplevel)
dir="$root/.superpowers/sdd"
mkdir -p "$dir"
printf '*\n' > "$dir/.gitignore"
