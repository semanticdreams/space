# External Unit Development MCP Design

## Purpose

Space already has robust in-app unit tooling for discovering, editing, testing,
reloading, and inspecting user units. The external OpenCode workflow should use
that same unit abstraction instead of editing user-unit files directly from the
Space repository checkout.

The goal is to add a Space-owned MCP surface for external development sessions.
OpenCode launched from this repository can connect to that MCP surface and work
on user units through loader-aware tools, while the normal Space repository
workflow remains unchanged.

## Problem

User units commonly live under Space's local user code directory, but that is an
implementation detail, not the contract. Future units may be backed by a local
filesystem directory, database records, remote hosts, generated stores, or other
loaders. A workflow that grants OpenCode direct filesystem access teaches the
wrong model and cannot generalize to non-filesystem units.

The current internal OpenCode MCP bridge is intentionally scoped to the in-app
agent provider. It starts a loopback MCP server, writes isolated OpenCode config,
and denies native OpenCode tools for internally spawned agent sessions. External
development from this repository needs a related but separate surface with an
explicit unit-development contract.

## Design

Add a second MCP entry point for external unit development. It should be separate
from the internal agent bridge, but reuse the same underlying Space unit systems
where possible.

The external surface exposes high-level unit operations, not raw paths. Tools
resolve units, inspect loader metadata, read source, apply patches, create files
when supported, run tests, reload units, and read logs through Space. Space owns
the loader-specific behavior, rollback, validation, approval risk labels, and
future support for non-filesystem sources.

The external OpenCode workflow treats a unit target as a resolved handle:

```text
unit-id: concrete registered unit id
loader: filesystem | database | remote | generated | unknown
source-handle: loader-defined opaque identifier
edit-capabilities: loader-supported operations
test-capabilities: loader-supported test operations
commit-capability: none | git | loader-versioned | remote-pr | unknown
```

OpenCode should never infer a user-unit path from the platform's Space user-data
code directory. That directory is a common current storage location, but the MCP
tool response is the authority.

## Tools

The external MCP should start with this minimal tool set:

- `space_unit_resolve`: Accept a vague natural-language description and return
  zero, one, or multiple candidate unit handles with confidence and evidence.
- `space_unit_list`: List registered units and loader metadata.
- `space_unit_inspect`: Inspect one unit's metadata, lifecycle exports,
  capabilities, source summary, and test summary.
- `space_unit_read_source`: Read a source artifact by unit handle and
  loader-relative source id.
- `space_unit_apply_patch`: Apply an exact or unified patch through the unit
  loader, then validate and reload when supported.
- `space_unit_create_source`: Create a new source artifact when the loader
  supports it.
- `space_unit_run_tests`: Run loader-defined unit tests.
- `space_unit_reload`: Reload the unit through Space's unit manager.
- `space_unit_read_log`: Read recent Space log lines, with optional filtering.
- `space_unit_snapshot`: Capture loader/runtime state when supported, for review
  and rollback evidence.

Existing internal unit tool implementations may be reused behind these external
tools, but the external contract should use loader-neutral names and responses
where the current internal tools are filesystem-oriented.

## Unit Resolution Workflow

The user should not need to know a unit id. Before editing, the workflow resolves
a concrete target:

1. Call `space_unit_resolve` with the user's description.
2. If exactly one high-confidence candidate is returned, use it.
3. If multiple plausible candidates are returned, ask the user to choose.
4. If no candidate is returned, ask whether to create a new unit or provide more
   context.

Resolution evidence may include unit id, module name, source summary, activity
registration, UI labels, log mentions, test filenames, loaded state, and loader
metadata.

## OpenCode Integration

Do not add Space-specific behavior to global `~/.config/opencode`.

Space repository guidance should document how to connect an external OpenCode
session to the external unit MCP endpoint. If OpenCode requires config files for
remote MCP, the repository should provide a helper that writes an isolated
temporary config rather than modifying the user's global config.

The normal Space repository development workflow remains the default for source
changes under this checkout. The external unit workflow applies only when the
task is about user units or loader-backed unit source outside the repository.

## Safety and Permissions

External unit development should not grant broad native filesystem access.

- Unit reads and writes go through Space MCP tools.
- Native OpenCode filesystem access is fallback-only and requires explicit human
  approval plus a Space-reported local filesystem source handle.
- The MCP server binds to loopback by default.
- Risk labels remain explicit for filesystem writes, shell/test execution,
  destructive operations, and remote actions.
- Tool responses must fail loudly when a loader lacks a requested capability.
- Patches should include stale-content protection where the loader can provide
  hashes or versions.

## Validation

The validation ladder for unit work is:

1. Resolve the intended unit and inspect its capabilities.
2. Add or update a focused unit test through the unit tooling when feasible.
3. Run the focused test through `space_unit_run_tests`.
4. Apply the implementation through MCP unit tools.
5. Re-run focused tests.
6. Reload the unit and inspect recent logs.
7. Run broader Space tests only when the unit change depends on modified engine,
   built-in asset, or app-level contracts.

Reviewer evidence should come from MCP tool transcripts, before/after source
content or loader versions, test output, reload result, and log checks.

## Documentation Updates

The implementation should update repository documentation to clarify:

- The Space user-data code directory is common local storage, not the unit contract.
- User units are loader-backed runtime objects.
- External OpenCode should use the external Space unit MCP surface by default.
- Direct filesystem edits are an escape hatch, not the normal workflow.

## Out of Scope

- Changing global `~/.config/opencode` to include Space-specific unit guidance.
- Replacing the existing internal agent MCP bridge.
- Implementing every future loader type.
- Building a general repository workbench for user units.
- Allowing non-loopback MCP binds by default.

## Acceptance Criteria

- External unit development has a separate MCP entry point from the internal
  agent bridge.
- OpenCode can connect to the external MCP without modifying global opencode
  config.
- A vague user description can be resolved to candidate unit handles before
  editing.
- Unit source changes go through Space loader-aware tools by default.
- Focused tests, reload, and log inspection are available through the MCP
  workflow.
- Documentation clearly separates Space repository development from external
  user-unit development.
