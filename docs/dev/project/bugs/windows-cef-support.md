---
type: bug
severity: medium
status: open
parent-goal: core-platform
tags:
  - bug
  - windows
  - cross-platform
created: 2026-07-14
---

# Windows CEF browser support

## Reproduction

The CEF in-world browser is Linux-only. No Windows CEF handler exists. The build system has MinGW QOS header conflicts requiring type stubs.

## Expected behavior

CEF embedded browser surfaces work on Windows, matching Linux parity.

## Actual behavior

Windows builds compile without CEF support. Browser surfaces fail to initialize on Windows.

## Impact

Windows is a primary distribution target. CEF browser surfaces are a core platform feature blocked from Windows users.

## Related

- Goal: [Core Platform](/dev/features/core-platform)
- Depends on: [CEF In-World Browser](/dev/features/cef-in-world-browser)
- See: [Windows Cross Platform](/dev/project/tech-debt/tech-debt-windows-cross-platform)
- See: [Bugs](/dev/project/bugs/)
