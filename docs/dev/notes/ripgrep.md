---
type: dev-note
tags:
  - note
---

# Ripgrep integration

## Overview

Programmatic ripgrep (`rg`) integration for file search within Space. The module spawns ripgrep as a subprocess, parses its `--vimgrep` output, and provides structured results. A companion `RipgrepView` widget wraps this with a search UI, result list, and external editor integration.

## Ripgrep module (`ripgrep.fnl`, 188 lines)

### API

- **`search(opts)`** — Runs ripgrep as a child process and returns parsed results. Options:
  - `:query` — search pattern (required)
  - `:paths` — array of paths to search (defaults to `["."]`)
  - `:cwd` — working directory for the process
  - `:case` — `:ignore`, `:sensitive`, or `:smart-case` (default)
  - `:hidden` — search hidden files
  - `:literal` — treat pattern as literal string
  - `:follow` — follow symlinks
  - `:word-regexp` — match whole words
  - `:max-count` — max matches per file
  - `:max-filesize` — skip files larger than given size (e.g. `"512K"`)
  - `:globs` — array of glob patterns to include
  - `:program-args` — additional args passed to ripgrep
  - `:timeout` — process timeout in seconds

- **`available?(opts)`** — Checks whether ripgrep is installed by running `rg --version`.

### Result format

```fennel
{:ok bool
 :cancelled bool
 :exit-code number
 :timed-out bool
 :stderr string
 :stdout string
 :matches [{:path string :line number :column number :text string}]
 :query string
 :paths [string]}
```

### Implementation

Uses the `process` Lua binding to spawn `rg --vimgrep --color never` with constructed args. The `--vimgrep` flag produces `path:line:column:text` output that is parsed with Lua pattern matching. Exit code 0 means matches found, 1 means no matches — both are considered `ok`. Non-zero/timed-out results produce empty match lists.

Supports cancellation via the process binding's cancel mechanism. The search function returns synchronously (blocks until the process exits).

## RipgrepView widget (`ripgrep-view.fnl`, 271 lines)

A composite search widget combining:
- **Search input** — Text input field with ripgrep query
- **Result list** — `ListView` rendering matches as clickable rows with truncated labels
- **Click to open** — Clicking a match opens the file at the matched line in an external editor via `ExternalEditor`

### Key constants

- `default-max-results` = 200
- `default-max-count-per-file` = 20
- `default-max-filesize` = `"512K"`
- `default-max-label-chars` = 180 (truncation threshold)

### Architecture

The view creates a `Flex` layout with:
1. Input row (query field + search button)
2. Result list (ListView with match labels)
3. Footer row (error/status display + clear button)

Each match label is formatted as `path:line — text...` truncated to `max-label-chars`. Clicking dispatches to `ExternalEditor` to open the file at the matched line.

## Integration with graph system

RipgrepView is used within the graph browsing workflow to search code directories and filesystem-backed graph nodes. Results can be linked to entities exposed through the graph for cross-referencing between search hits and graph-visible objects.


## See also

- [Core Platform](/dev/features/core-platform)
