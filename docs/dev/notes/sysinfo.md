# Sysinfo Module

The `sysinfo` module exposes psutil-style system and process monitoring to Lua/Fennel.

## Usage

```fennel
(local sysinfo (require :sysinfo))
```

## Top-Level API

- `(sysinfo/platform)` -> map:
  - `:os`, `:arch`, `:lua`, `:features`
- `(sysinfo/system)` -> `System` object
- `(sysinfo/sleep seconds)` -> convenience sleep helper

## System API

- `(sys:refresh)` -> boolean
- `(sys:cpu-usage)` -> `{:percent :warmup :interval :per-core}`
- `(sys:cpu-times)` -> cumulative counters map
- `(sys:mem-virtual)` -> `{:total :used :available :free :percent}`
- `(sys:process-current)` -> `Process`
- `(sys:process pid)` -> `Process` or `nil`
- `(sys:process-list opts)` -> sequence of `Process`

## Process API

Process objects expose:

- `p.pid` -> pid number
- `(p:exists)` -> boolean
- `(p:name)` -> string or nil
- `(p:refresh)` -> boolean
- `(p:cpu)` -> `{:percent :warmup :interval}`
- `(p:cpu-times)` -> `{:user :system}`
- `(p:mem)` -> `{:rss :vms :percent}`

## CPU Sampling Semantics

CPU usage is delta-based and stateful:

- First `(sys:cpu-usage)` and first `(p:cpu)` return warmup:
  - `{:percent nil :warmup true ...}`
- `refresh` also records a sample baseline; two refreshes across time are sufficient to warm subsequent CPU reads.
- Subsequent calls after elapsed time compute percent from the delta between samples.
- No internal blocking/sleep is required; callers sample naturally in their own update loop.

## Platform Behavior

The API surface is stable across Linux, Windows, and macOS. Fields unsupported on a given platform resolve to `nil`, and feature availability is advertised via `(sysinfo/platform).features`.
