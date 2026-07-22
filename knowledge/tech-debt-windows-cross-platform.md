---
type: tech-debt
impact: medium
effort: large
status: in-progress
tags:
  - tech-debt
  - windows
  - cross-platform
  - build
created: 2026-07-14
updated: 2026-07-14
---

# Windows cross-platform hardening

## Where

Build system (`cmake/`), C++ engine (`src/`), Fennel runtime (`assets/lua/`)

## Problem

The project was developed on Linux. Porting to Windows revealed 10+ categories of issues concentrated in a 2-day sprint (June 17-18, 2026):

- MinGW QOS header conflicts requiring type stubs and conditional compilation
- Backslash vs forward slash path separator divergence in Fennel module resolution, unit file resolution, and hot-reload path matching
- CRLF line endings corrupting clipboard content
- `.exe` suffix missing from binary search paths in tests
- Fennel cache keys using forward slashes regardless of platform

## Why it matters

Windows is a primary distribution target (Windows installer, .zip in releases). Without cross-platform hardening, every new feature risks introducing platform-specific bugs.

## Plan

The June sprint resolved the known issues. Remaining concerns:
- Ongoing vigilance: new path manipulation code must handle both separators
- CI covers cross-compile for MinGW but not full Windows-native builds
- Some features (CEF in-world browser) are Linux-only with no Windows handler yet

## Related

- Goal: [[core-platform]]
- See: commits from 2026-06-17 to 2026-06-18
- Blocks: broader Windows feature parity (CEF, audio devices)
