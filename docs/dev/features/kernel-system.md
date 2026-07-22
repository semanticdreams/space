---
type: feature
status: shipped
parent-goal: core-platform
tags:
  - feature
  - kernel
  - repl
  - shell
  - zmq
created: 2026-07-14
updated: 2026-07-14
---

# Kernel system

## Summary

Interactive computational kernel manager providing Fennel REPL and shell execution with ZeroMQ-based communication. 739 lines of Fennel. Kernels are persisted as JSON files, with history tracking and instance lifecycle management.

## Motivation

Space needed an in-application computation environment that feels native to the spatial workspace. Rather than shell out to an external terminal, kernels provide REPL and shell sessions as first-class application objects with state persistence, history, and communication channels.

## Design

- **Kernel instances**: Each kernel is a named entity with a `command` (Fennel REPL or shell), working directory, and list of startup input lines. Persisted as JSON in `{data-dir}/kernels/`.
- **Lifecycle**: `create` allocates a kernel with a UUID and returns the new object via a `created` signal. `run` starts the process (Fennel evaluator or shell subprocess). `kill` terminates it. Kernels auto-save on state changes.
- **Fennel REPL**: Uses `FennelEvaluator` for in-process Fennel code evaluation with result capture.
- **Shell execution**: Spawns child processes via `process` binding, capturing stdout/stderr. Supports stdin input.
- **ZeroMQ communication**: Kernels communicate via ZMQ PUB/SUB sockets, allowing kernel-to-kernel data exchange. Each kernel publishes on a dedicated topic.
- **History**: Each kernel maintains a history of inputs and outputs. History is persisted alongside kernel config.
- **Signals**: Emits `created`, `removed`, `updated` signals. Signal subscribers can react to kernel state changes (e.g., UI updates when kernel output arrives).

## Tasks

- [x] Kernel instance create/run/kill lifecycle
- [x] Fennel REPL evaluation
- [x] Shell command execution with stdin/stdout/stderr
- [x] ZMQ PUB/SUB communication between kernels
- [x] JSON persistence with history
- [x] Signal emission for state changes

## Related

- Goal: [Core Platform](/dev/features/core-platform)
- See: [Subsystems](/dev/subsystems/) — Application Features section
- See: [Kernels](/dev/notes/kernels)
- See: `fennel-interpreter-view.fnl` — REPL UI widget
