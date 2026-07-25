# README Slimdown Design

**Date:** 2026-07-25
**Status:** Approved

## Goal

Convert `README.md` from a 396-line developer-heavy document into a ~50-line friendly landing page. Move all detailed content into `docs/` under the appropriate user/dev sections.

## Audience

"Everyone" — users evaluating the project, contributors wanting to build from source, and people who just want to install prebuilt releases. The README is a front door with clear signposts for each audience.

## New README Structure

```
# space

[CI badge] [Build badge] [License badge]

> Free Your System — a programmable, shared, user-owned computing
> environment for code, knowledge, games, art, and collaboration.

[Quick Start] · [User Docs] · [Developer Docs] · [Latest Release]

## What is space?

Brief paragraph (~4 sentences). Four feature bullets borrowed from docs/index.md:
- Spatial Computing
- Live Programming
- Shared Worlds
- User-Owned Infrastructure

## Getting Started

Prebuilt packages: link to latest release page.
Build from source: link to docs/dev/building.md.

## Contribute

Discussions · Matrix

## License

GPL v3
```

## Content Migration Map

| README section | Destination | New file? |
|---|---|---|
| Install from release (artifact list + guidance) | `docs/user/quick-start.md` | No (update existing) |
| Build from source (distro deps + CI markers) | `docs/dev/building.md` | Yes |
| Packaging, AppImage, release scripts | `docs/dev/building.md` | Yes |
| Remote Control / debugging | `docs/dev/remote-control.md` | Yes |
| Terminal widget | `docs/dev/terminal.md` | Yes |
| E2E Snapshot Tests | `docs/dev/e2e-testing.md` | Yes |
| In-World Video (FFmpeg) | `docs/dev/video-playback.md` | No (already exists) |
| Profiling | `docs/dev/profiling.md` | Yes |
| CEF browser API examples | `docs/dev/features/cef-in-world-browser.md` | No (already exists) |

## Critical Dependencies

1. **CI dependency extraction:** `.github/workflows/test.yml` and `build.yml` parse the Ubuntu package list from README.md using `CI_DEPS_START` / `CI_DEPS_END` markers. These markers must move to `docs/dev/building.md` and the workflows updated to point there.

2. **quick-start.md is a stub:** `docs/user/quick-start.md` currently points users back to README. It must become self-sufficient with release install guidance.

3. **Cross-references:** Some docs pages (e.g., CEF browser docs) reference README as the canonical source. These must be updated to point to the new pages.

## Sidebar / Nav Updates

- `docs/.vitepress/config.mts`: add new dev pages to the Developer sidebar.
- `docs/dev/index.md`: add links to all new dev pages.
- `docs/user/index.md`: ensure it directs to Quick Start (not README).

## Out of Scope

- Changing build commands, package names, release artifact names, runtime behavior, or feature APIs.
- Rewriting or revalidating the content being moved — move as-is, link correctly.
