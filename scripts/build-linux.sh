#!/usr/bin/env bash
set -euo pipefail

cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release

(
    cd build
    cpack -G DEB
)

mkdir -p build/dist
rm -rf build/dist/assets
cp -r assets build/dist/assets
cp build/space build/dist/
tar -czf build/dist/space-linux-x86_64-bin.tar.gz -C build/dist space assets
