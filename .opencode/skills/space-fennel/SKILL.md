---
name: space-fennel
description: Use when editing assets/lua/**/*.fnl, Fennel tests, Fennel constraints, or Space Fennel CLI/MCP tools; provides validation commands, syntax traps, macro path requirements, and parser-repair workflow.
---

# Space Fennel

Use this skill for all Space `.fnl` work: Fennel source under `assets/lua/`,
Fennel tests, Fennel constraints, and Fennel validation CLI/MCP tools. When the
work is specifically about widgets, layout, rendering adapters, interaction
widgets, widget lifecycle, or widget tests, use `space-fennel-ui` additionally.

## Validation Ladder

Run validation in this order and report evidence in the same order:

1. **Compile check** — run `make fennel-check` for broad changes, or use the
   touched-file command for narrow edits:
   ```bash
   ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/foo.fnl
   ```
2. **Constraints** — run `make constraints` or the relevant explicit-file
   constraints path after the compile check.
3. **Focused Fennel tests** — run the smallest test command that covers the
   changed behavior.
4. **Broader suite** — run the broader relevant suite, normally `make test` for
   final whole-project validation.

`make constraints` and `make test` include the compile gate transitively, but
agents should still prefer the earlier compile step for fast feedback on changed
`.fnl` files.

## Unsupported Validation Oracles

Do not use system `fennel`, system `lua`, `fennel-ls`, `fnlfmt`,
`./build/space --compile`, or `./build/space -e` as proof that Space Fennel is
valid. Space validation must go through the vendored compiler and runtime via
`tools.fennel-check`, constraints, and tests.

## Macro And Runtime Paths

Direct `./build/space -m ...` Fennel test runs need the normal Space runtime
environment. Set `SPACE_ASSETS_PATH=$(pwd)/assets`, and set both `FENNEL_PATH`
and `FENNEL_MACRO_PATH` to:

```text
$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl
```

Also use the standard test hygiene from `space-testing-runtime`:
`SPACE_DISABLE_AUDIO=1`, `XDG_DATA_HOME=/tmp/space/tests/xdg-data`, and
`SKIP_KEYRING_TESTS=1` for test commands when applicable.

## Syntax Traps And Repair Workflow

- Prefer project idioms from `AGENTS.md`: `local` instead of `let`, multi-branch
  `if` instead of nonexistent `cond`, direct multiple-value bindings for
  `pcall`, and factory functions instead of `.new` constructors.
- Fennel parse errors often point at the location where parsing failed, not the
  form that caused the failure.
- For delimiter or parenthesis imbalance, inspect the nearest enclosing form
  before editing. Use `space_fennel_enclosing_form` (or the underlying service)
  around the reported line/column, repair the smallest malformed enclosing form,
  then rerun the compile check first.
- If the enclosing form is deeply nested or hard to balance, simplify by moving
  logic into helper functions rather than adding more delimiters by guesswork.

## MCP Inspection Tools

Use read-only MCP tools for targeted inspection when available:

- `space_fennel_check_file`
- `space_constraints_check_files`
- `space_fennel_parse_tree`
- `space_fennel_enclosing_form`
- `space_fennel_structure_metrics`

These tools are inspection/validation aids only. Do not introduce write-capable
MCP tools or automatic AST rewriting as part of normal repair work.

## Handoff Evidence

Fennel reports should include:

- compile-check command and result;
- constraints command and result, plus constraint-impact note when relevant;
- focused test command and result;
- broader-suite command and result when required by the task.
