# Stable Fennel Constraints Design

## Summary

The constraints feature is no longer experimental. Current, active project references should describe it as the stable Fennel constraints gate. This is a terminology and identifier cleanup only: validation behavior, runner semantics, constraint rules, baseline policy, and the `make constraints` workflow remain unchanged.

## Context

The feature is already blocking in local validation, CTest, CI, and agent handoffs. Keeping the `experimental` qualifier now creates confusing mixed signals: the gate is mandatory, but the wording implies provisional behavior. The user explicitly requested removing `experimental` everywhere because it is meaningless.

Exploration found active references in:

- repository workflow docs (`AGENTS.md`);
- the canonical constraints docs page (`docs/dev/experimental-constraints.md`) and docs index;
- GitHub Actions step labels;
- CMake/CTest test and fixture identifiers;
- constraint source module header comments;
- integration configuration tests that assert CMake wiring;
- project-local OpenCode skills that point agents at the constraints docs.

Historical design specs and implementation plans under `docs/specs/**` and `docs/plans/**` record past work and should not be rewritten as part of this cleanup.

## Approaches Considered

### 1. Prose-only cleanup

Remove `experimental` from docs prose while preserving file paths and test identifiers such as `docs/dev/experimental-constraints.md` and `space_experimental_constraints`.

- Pros: lowest compatibility risk for existing commands and links.
- Cons: leaves the meaningless term in visible active filenames, URLs, and CTest output.

### 2. Full active rename (selected)

Rename active docs, CI labels, CTest identifiers, tests, comments, and agent references to stable constraints naming.

- Pros: satisfies the request directly; active tooling no longer advertises the feature as experimental.
- Cons: old direct links and old `ctest -R space_experimental_constraints` commands stop matching.

### 3. Full rename with aliases/redirects

Add compatibility aliases for old CTest names or docs paths.

- Pros: preserves older command/link compatibility.
- Cons: keeps the obsolete term alive and adds maintenance surface for a one-time cleanup.

## Design Direction

Use the full active rename without aliases. The stable names are:

- docs page: `docs/dev/constraints.md`;
- docs title/link text: `Fennel Constraints`;
- CTest test: `${PROJECT_NAME}_constraints`;
- CTest fixture: `space_constraints`;
- CI step: `Run constraints`.

Keep stable implementation entry points unchanged:

- `make constraints`;
- `constraints.runner:main`;
- `assets/lua/constraints/**` module paths;
- runner statuses (`pass`, `violations`, `fail`, `interrupted`);
- baseline semantics and rule behavior.

## Components and Data Flow

The Make target continues to invoke the constraints runner over repository Fennel sources. CTest continues to require the constraints fixture before Fennel test targets, but the fixture and test names use stable terminology. GitHub Actions continues to run `make constraints` explicitly after the Linux build; only the displayed step name changes. Documentation and agent workflow references point to the renamed canonical docs page.

## Error Handling and Compatibility

The cleanup should not change runner error handling or exit codes. Every non-`pass` status remains blocking.

Expected compatibility changes:

- Replace `ctest -R space_experimental_constraints` with `ctest -R space_constraints`.
- Replace `/dev/experimental-constraints` and `docs/dev/experimental-constraints.md` with `/dev/constraints` and `docs/dev/constraints.md` in active repo references.

No compatibility alias is required because the stated goal is to remove the obsolete term from active usage.

## Testing and Validation

Validation should prove both naming and behavior:

1. Search active files for stale constraints-related experimental terminology, excluding historical plans/specs and unrelated external uses.
2. Re-run CMake configuration so renamed CTest identifiers are generated.
3. Run `make constraints` to confirm runner behavior remains green.
4. Run a focused CTest command covering the renamed constraints test and dependent Fennel tests.
5. Run the broader relevant test suite (`make test`) before completion.

For Fennel-facing edits, follow the project validation ladder: compile check first, constraints second, focused Fennel tests third, broader suite last.

## Out of Scope

- Changing constraint rules, diagnostics, output formats, targets, or baseline policy.
- Renaming the `make constraints` target.
- Renaming `constraints.runner` or the `assets/lua/constraints/**` module directory.
- Rewriting historical specs/plans or unrelated references to other experimental features/tools.
