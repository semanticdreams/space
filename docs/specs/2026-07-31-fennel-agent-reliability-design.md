# Fennel Agent Reliability Design

## Purpose

Implementer agents still lose time on Fennel syntax and parser-repair loops even
after the experimental constraints system and project-local OpenCode workflow
guidance were completed. Constraints now provide the repository's structural and
architectural intelligence layer, but they are not an authoritative compile-only
syntax oracle. This design completes the follow-up by adding project-native
Fennel validation tools, wiring them into agent workflows, and exposing the same
capabilities through MCP once the command-line contract exists.

## Evidence

OpenCode session analysis for implementer sessions in this Space worktree
between 2026-07-27 and 2026-07-31 found 121 implementer sessions. Bash outputs
contained Fennel parse/syntax/compile-style errors in 58 sessions. Overlapping
dominant patterns were:

- expected closing delimiter: 41 sessions;
- unexpected closing delimiter: 31 sessions;
- expected expression/value: 66 sessions;
- invalid string: 2 sessions;
- macro/import compile-error language: 12 sessions.

Agents repeatedly tried unavailable or unsupported compile checks such as system
`fennel --compile`, system `lua assets/lua/fennel.lua --compile`, `./fennel`,
`./build/space --compile`, and `./build/space -e`. No implementer LSP or MCP
tool invocations were found. Tree-sitter was mostly used indirectly through the
constraints system or via ad-hoc runtime snippets. Post-workflow-completion
evidence is limited because only a few later sessions exist and they were mostly
documentation or CI work.

## Design Direction

Build the full reliability stack in layers, with each layer useful on its own:

1. **Compiler-backed Fennel check** — a Space-native CLI and Make target that
   compiles repository Fennel with vendored `assets/lua/fennel.lua` inside the
   normal `./build/space` runtime. This is the fast first-stage syntax oracle.
2. **Structural constraints** — keep the completed constraints system as the
   second-stage project intelligence gate for nesting, size, style doctrine,
   lifecycle, layout, scene, sandbox, and test-isolation contracts.
3. **Agent validation ladder** — make implementer, planner, reviewer, testing,
   and Fennel skill guidance converge on the same ladder: compile check,
   constraints, focused tests, broader suite.
4. **Project-specific MCP tools** — expose the same stable service layer through
   MCP tools for agents that can use tool calls directly. MCP wraps the CLI
   behavior and tree-sitter/constraint facts; it does not replace the blocking
   Make targets.
5. **Deferred optional integrations** — treat `fennel-ls`, `fnlfmt`, and
   higher-level AST editing as optional follow-ups after the native service and
   MCP tools prove useful.

This favors project-native accuracy over generic editor integration. Generic
LSP support can be added later, but the foundation should remain accurate if
Space changes its Fennel conventions, adds pre-compilation steps, or needs
repository-specific facts that a generic Fennel server cannot know.

## Components

### Fennel validation service

Add a reusable service module that owns Fennel source validation and structural
queries without depending on MCP transport. It should support:

- compiling one file, explicit file sets, or the repository target using
  vendored Fennel and the same module/macro paths as normal Space tests;
- deterministic diagnostics containing file path, line/column when available,
  compiler message, and a concise repair hint for delimiter/form errors;
- tree-sitter parse-tree queries for a file;
- enclosing-form lookup around a file/line/column or byte offset;
- structure metrics for nesting, function length, and module length;
- constraints checks for explicit file lists by delegating to the existing
  constraints target resolver/runner behavior where clean.

The service should be testable without an MCP server and should never rely on
system `fennel`, system `lua`, or unavailable `./build/space` flags.

### CLI and Make targets

Add Space-native commands that agents can run reliably:

```bash
make fennel-check
./build/space -m tools.fennel-check:main -- --target repo
./build/space -m tools.fennel-check:main -- --target files --file assets/lua/foo.fnl
```

`make fennel-check` should use the same canonical runtime environment as
constraints and tests. `make constraints` should run the compile check before
structural constraints so `make test` remains transitively gated.

The Makefile should avoid hand-copying Fennel runtime variables across targets;
shared variables or a small reusable command prefix should preserve the current
environment while reducing future copy/paste mistakes.

### MCP tools

Expose project-specific MCP tools after the CLI/service layer exists. The
initial tool set should be read-only and should use the established
service/tools/bridge pattern from the existing MCP subsystems:

- `space_fennel_check_file` — compile one `.fnl` file and return concise
  diagnostics;
- `space_constraints_check_files` — run constraints against explicit files;
- `space_fennel_parse_tree` — return a bounded tree-sitter parse summary;
- `space_fennel_enclosing_form` — return the enclosing form around a location;
- `space_fennel_structure_metrics` — return nesting/function/module metrics.

MCP tools should be loopback-only by default, use project-local isolated config
when launching OpenCode-facing servers, label filesystem-read risk accurately,
and avoid write/edit tools in this slice. They should wrap the project-native
service, not duplicate parser/compiler logic.

### Agent, skill, and documentation guidance

Create a general Fennel workflow reference and update repo-local OpenCode
guidance to make the validation ladder explicit.

For `.fnl` changes, implementers should run:

1. a fast compile check for touched files or `make fennel-check`;
2. relevant constraints, preferably explicit files when the task is narrow;
3. focused Fennel tests;
4. the broader relevant suite, with `make test` for final validation.

Planner guidance should name exact commands for Fennel tasks. Reviewer guidance
should treat missing compile/constraints/focused-test evidence as a validation
gap when relevant. Implementer reports should include command/output evidence
for compile check, constraints, focused tests, and the existing constraint-impact
note.

The existing UI-specific Fennel skill should remain for widget/layout/rendering
doctrine. Add a general Space Fennel skill for all `.fnl` work or broaden the
project-local guidance so non-widget Fennel work receives syntax traps,
validation commands, macro-path requirements, and parser-repair workflow.

### Repair workflow

Guidance and tool output should steer agents away from manual paren-counting:

- on delimiter errors, run the file compile check and inspect the enclosing form;
- if the failing region is deeply nested, extract named helpers before adding
  more logic;
- when parser locations look misleading, isolate the bad form with a structured
  query or temporary narrowing rather than guessing at the reported closing
  delimiter;
- avoid ad-hoc shell snippets unless a project-native command cannot answer the
  question.

## Options Considered

### Native CLI plus MCP wrapper (chosen)

This approach gives every agent a reliable command-line path and later exposes
the same behavior through MCP. It directly addresses the session evidence that
agents tried unsupported compile commands and did not use LSP/MCP tools.

### Fold compiler diagnostics directly into constraints only

This keeps one command, but it conflates syntax validation with structural
project contracts. A broken file can produce noisy secondary structural output.
The chosen design still makes constraints transitively run the compile gate, but
keeps the first-stage command separately usable.

### Base the solution on `fennel-ls`, `fnlfmt`, or generic Tree-sitter editing

These may become useful, but session evidence found no LSP usage and no
`fnlfmt`/`fennel-ls` usage. They also cannot encode Space-specific constraints
as directly as the completed constraints system. The project-native service is
the foundation; generic editor integrations remain optional.

## Error Handling

- Compile check failures exit nonzero and print concise diagnostics. They should
  not emit ALSA/OpenAL noise in normal Make usage.
- File-target commands should reject non-Fennel files with a clear diagnostic.
- Missing build artifacts should report that `make build` is required, matching
  existing Make dependencies rather than trying system interpreters.
- Constraint failures keep their existing statuses: `pass`, `violations`,
  `fail`, and `interrupted`.
- MCP tools should return structured error payloads rather than crashing the
  server on bad file paths, parse failures, or invalid locations.

## Testing

Implementation should add focused Fennel tests for:

- valid file compile succeeds;
- malformed delimiter syntax fails with file/message diagnostics;
- file-target mode checks only requested files;
- Makefile environment refactor preserves constraints/test commands;
- constraints still run after the compile gate;
- MCP tool wrappers call the same service behavior and return structured
  diagnostics;
- tree-sitter enclosing-form and structure-metric tools work on representative
  valid Fennel and degrade predictably on invalid Fennel.

Final validation should include `make fennel-check`, `make constraints`, focused
new tests, and the standard full suite command from `AGENTS.md`.

## Out of Scope

- Replacing the constraints system with generic Tree-sitter analysis.
- Making LSP the primary solution.
- Requiring system `fennel`, system `lua`, `fennel-ls`, or `fnlfmt`.
- Automatic AST rewriting or production code editing through MCP.
- Broad formatting churn unrelated to syntax reliability.

## Acceptance Criteria

- A project-native Fennel compile check exists and is runnable through Make and
  `./build/space -m ...`.
- The check uses vendored Fennel and canonical Space runtime/module/macro paths.
- Explicit-file mode works for touched-file workflows.
- `make constraints` runs after the compile gate, and `make test` remains
  transitively gated.
- Agent and skill guidance documents the compile → constraints → focused tests
  → broader suite ladder.
- Reviewer guidance verifies compile/constraints evidence for relevant Fennel
  diffs.
- MCP exposes read-only project-native tools for Fennel compile diagnostics,
  constraints-by-file, parse summaries, enclosing forms, and structure metrics.
- The design explicitly defers LSP, `fnlfmt`, and AST rewriting until the native
  CLI/service/MCP layer is stable.
