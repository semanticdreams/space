# Experimental Fennel Constraints Design

## Purpose

Add a blocking, experimental constraint system for the Fennel codebase. The
system should detect architectural regressions, invalid interactions, lifecycle
leaks, layout/rendering contract violations, and code-structure problems before
normal tests run and before implementer work is handed to reviewer.

This is explicitly an experiment. Constraints should be enforced from the start
so the team learns whether they are useful under real pressure. If a constraint
is noisy or wrong, the remedy is to fix it or remove it through reviewed code,
not to bypass the gate.

## Scope

The first version combines static source analysis and executable scenario
constraints:

- static facts from Fennel source using the vendored tree-sitter Fennel parser;
- executable constraints that instantiate real modules and check system-level
  behavior;
- structured diagnostics and a single blocking result;
- tests for the runner, fact extraction, and each constraint family;
- integration into the normal validation flow with `make constraints` and a
  CTest target that runs before Fennel tests.
- support for checking targets outside the main repository file set, including
  user units, app-specific scripts, and other Fennel modules that run on the
  Space runtime.

The MVP does not need a general query language, complete semantic analysis,
macro-expanded analysis, or broad lint coverage. Those can be added after the
first constraints prove useful.

## Architecture

The system has four stable boundaries:

1. **Code under examination**: one or more configured analysis targets. The
   default target is the repository Fennel code under `assets/lua/`, but the
   runner must also accept external roots or explicit files for user units,
   app-specific scripts, and other Space-runtime Fennel code. Production modules
   do not import or call constraint modules.
2. **Facts made available for examination**: parsed source facts and selected
   executable scenario observations.
3. **Constraints**: Fennel modules that encode acceptable system behavior.
4. **Diagnostics**: structured reports explaining violations, framework
   failures, or interruptions.

### Static source facts

The existing tree-sitter binding should be extended to expose Fennel parsing,
preferably through a language-selecting API such as `parse(source,
{:language :fennel})`. The Fennel parser is already vendored in the repository;
the binding should only expose parse capability and source locations.

A Fennel facts layer walks parsed files and records facts such as:

- module path and source file;
- `require` dependencies;
- top-level function and local definitions;
- exported table keys;
- function calls and method calls;
- table/member accesses such as `world.state.scene`, `app.renderers`, and
  `package.loaded`;
- mutation sites, especially `set` forms against shared globals;
- approximate function length, module length, nesting depth, table literal size,
  and anonymous callback depth.

The MVP should expose traversal helpers and fact tables only. It should not
attempt to build a general-purpose query language before the first rules are in
use.

### Analysis targets

The runner should treat the repository as the default analysis target, not the
only possible target. A target describes a set of source roots or explicit files,
the module path assumptions needed to parse them, and the constraint suites that
apply to them.

Supported target kinds should include:

- `:repo`: the default project code and tests under `assets/lua/`;
- `:unit`: user-authored units or generated unit source that run through the
  Space unit system;
- `:app`: app-specific Fennel entry points or scripts using the Space runtime;
- `:files`: explicit standalone files passed to the runner.

Not every constraint applies to every target. Repo architecture constraints such
as Scene/Sandbox ownership apply to `:repo`. General source, lifecycle, layout,
and structure constraints should be reusable for external targets when their
facts are available. Diagnostics should always identify the target as well as the
file and constraint id.

### Executable scenario facts

Some contracts are behavioral and cannot be usefully proven by source scans.
Scenario constraints run through the normal `build/space -m ...` Fennel runtime,
construct real modules where practical, and check broad system contracts. These
constraints should remain architectural and cross-cutting rather than becoming
local unit tests.

Examples include activity-slot isolation, Sandbox activation behavior, service
reset after slot switches, and layout/rendering ownership expectations.

## Execution model

The system runs as a blocking gate before normal tests:

```bash
make constraints
make test
```

The same runner should also support explicit target execution, for example a
single user unit source root or a set of standalone scripts. The exact CLI flags
can be chosen during implementation, but the design requires a non-repo entry
point so other Space-runtime code can be checked without being copied into
`assets/lua/`.

`make test` and the CTest Fennel test targets should depend on the constraints
target so constraints cannot silently disappear from the normal workflow.

Each constraint runs independently and contributes to one aggregate result:

- `pass`: all constraints completed and emitted no diagnostics;
- `violations`: one or more constraints completed and reported rule violations;
- `fail`: a constraint or framework component crashed unexpectedly;
- `interrupted`: a timeout or interruption stopped evaluation.

Every status other than `pass` exits nonzero. The runner emits one structured
summary containing status, counts by family/severity, and all diagnostics.

## Diagnostics

Every diagnostic should include:

- constraint id;
- family;
- severity;
- message;
- source file and line/column when available;
- relevant evidence or related locations;
- a short repair hint when the fix is not obvious.

Diagnostics should be actionable enough for an implementer to fix without
needing to rediscover the rule intent from scratch.

## Constraint families

The first implementation should include four families. The family mix is
intentional: it tests whether the system is generally useful, not merely whether
it can encode one Scene/Sandbox branch review.

### 1. Scene/Sandbox architectural contracts

Initial constraints:

1. **No legacy Scene consumers**: forbid `world.state.scene.*` access outside
   explicit migration or normalization allowlists.
2. **Activity Scene slot ownership**: Graph, Drawing, and Board must ensure and
   activate their own Scene slots, never Sandbox's slot.
3. **Sandbox activation contract**: Sandbox activation must require
   `runtime.scene`, activate the Sandbox slot, hide Canvas, prefer Scene
   interaction, install root actions, install target predicate, and install the
   update hook.
4. **Active render context routing**: Scene render/accessor paths must resolve
   active slot context when a slot is active.

### 2. General lifecycle contracts

Initial constraints:

1. **Event/registration cleanup**: modules that connect events, register update
   hooks, or register with global systems must disconnect/unregister/drop in
   cleanup paths.
2. **Global mutation restoration in tests**: tests that mutate sensitive globals
   such as `app.renderers`, `app.lights`, `app.engine`, `app.activity-registry`,
   `app.physics-containment-config`, or `package.loaded` must restore them.
3. **No silent required-runtime fallback**: required runtime dependencies should
   assert or error rather than silently no-op or synthesize canonical state.

### 3. Layout/rendering contracts

Initial constraints:

1. **No layout setter calls inside layouters**: layouters should mutate child
   layout fields directly rather than call setters that dirty layout mid-pass.
2. **Owned child drop contract**: widgets/entities that create retained child
   entities or layouts must drop them in their own `drop` path.
3. **Interactive context assertion**: interactive widgets that require
   `clickables` or `hoverables` must assert the required context instead of
   silently guarding around missing routing services.

### 4. Formatting and code-structure contracts

Initial constraints:

1. **Maximum nesting depth**: flag overly nested functions/forms.
2. **Maximum function length**: flag oversized functions.
3. **Maximum module length**: flag oversized modules.
4. **Large inline structure/callback checks**: flag very large table literals and
   deeply nested anonymous callbacks.
5. **Style doctrine checks**: enforce repo-specific Fennel structure rules such
   as avoiding `let`, avoiding silent fallback patterns, and avoiding new
   compatibility aliases unless explicitly allowlisted.

## Baseline and allowlist policy

Structure and formatting constraints must be blocking immediately without
requiring a large cleanup branch first. Existing violations may be represented in
an explicit reviewed baseline or allowlist. The baseline is not a bypass flag; it
is versioned project data that records known exceptions with file, rule, current
measure, and reason.

The gate blocks when:

- a new violation appears;
- an existing baseline violation worsens;
- a baseline entry no longer matches the current code;
- a required constraint disappears;
- a constraint fails or is interrupted.

When code improves, the baseline should shrink. Removing stale baseline entries
is part of keeping the system honest.

## Components

### C++ binding

- Extend the existing tree-sitter Lua binding to parse Fennel.
- Prefer a generic language parameter if practical.
- Preserve source range access for diagnostics.

### Constraint core

- `assets/lua/constraints/runner.fnl`: discovery, execution, aggregation,
  timeout handling, process exit behavior.
- `assets/lua/constraints/diagnostics.fnl`: diagnostic normalization and result
  shaping.
- `assets/lua/constraints/source.fnl`: file discovery, file reading, parse
  wrapper, AST traversal helpers.
- `assets/lua/constraints/facts.fnl`: stable fact extraction from Fennel source.
- `assets/lua/constraints/targets.fnl`: target configuration, source-root/file
  resolution, and suite selection for repo, user-unit, app, and explicit-file
  runs.
- `assets/lua/constraints/baseline.fnl`: reviewed baseline loading and checking.

### Constraint modules

- `assets/lua/constraints/rules/scene-sandbox.fnl`
- `assets/lua/constraints/rules/lifecycle.fnl`
- `assets/lua/constraints/rules/layout.fnl`
- `assets/lua/constraints/rules/structure.fnl`
- `assets/lua/constraints/rules/test-isolation.fnl`

### Tests

- `assets/lua/tests/test-constraints-runner.fnl`
- `assets/lua/tests/test-constraints-source.fnl`
- `assets/lua/tests/test-constraints-facts.fnl`
- `assets/lua/tests/test-constraints-rules-*.fnl`

Each constraint must have focused tests for at least one valid input and one
invalid input. Scenario constraints should also prove their diagnostics contain
the expected id and relevant evidence.

## Integration

Add a `make constraints` target using the same runtime conventions as Fennel
tests: `SPACE_DISABLE_AUDIO=1`, absolute `SPACE_ASSETS_PATH`, and configured
`FENNEL_PATH` / `FENNEL_MACRO_PATH`.

The Make target should run the default repo target. The underlying runner should
also expose a way to run constraints against non-repo targets, such as user units
or app scripts, while still using the Space runtime and the same diagnostic
schema.

Add a CTest target for experimental constraints and make normal Fennel tests
depend on it. The target name and docs should keep the word `experimental`, but
the target must be blocking.

Update repository documentation so implementers know to run constraints before
tests and understand the four result statuses.

## Success criteria

The experiment is useful if it quickly catches real issues that previously
reached reviewer, with diagnostics clear enough for implementers to repair.

Concrete acceptance criteria:

- `make constraints` exists and exits nonzero for `violations`, `fail`, or
  `interrupted`.
- `make test` cannot run Fennel tests without first running constraints.
- The static Fennel parser path records source locations for diagnostics.
- The runner can analyze at least one explicit non-repo file/root target without
  requiring that source to live under `assets/lua/`.
- The first rule set covers Scene/Sandbox, lifecycle, layout/rendering, and
  structure/formatting families.
- Every rule has valid and invalid tests.
- Existing structure violations are represented by explicit reviewed baseline
  entries rather than ignored implicitly.

## Non-goals

- Do not replace human review.
- Do not replace unit/integration tests.
- Do not require production modules to annotate themselves or import constraint
  modules.
- Do not build a full static type system or macro-expanded semantic analyzer in
  the MVP.
- Do not make constraints advisory-only; if they are bad, fix or remove them.
