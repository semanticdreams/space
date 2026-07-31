# Experimental Fennel Constraints

The experimental constraints gate checks repository Fennel code before normal Fennel tests run. It combines source facts from the Fennel parser with executable scenario checks so structural, lifecycle, layout, rendering, Scene, and Sandbox mistakes are caught early.

The gate is still explicitly experimental, but it is blocking. If a constraint is noisy or wrong, fix or remove that constraint through normal reviewed code. Do not bypass the gate.

## Daily Workflow

Run the constraints gate before focused Fennel test runs:

```bash
make constraints
```

`make constraints` runs the default repository target over `assets/lua/` with the runtime environment configured for the Space asset tree and Fennel module paths. A clean repository run exits successfully with status `pass` and 0 diagnostics.

`make test` already depends on `make constraints`, so full test runs execute the experimental constraints gate first. You do not need to run `make constraints` separately immediately before `make test`, but running it before narrowed Fennel tests gives faster feedback and keeps focused runs honest.

## Agent Workflow

Treat experimental constraints as early feedback that reduces review and fix cycles, not as a ritual to satisfy after the fact. For Fennel-facing implementation work, run `make constraints` before narrowed Fennel test commands when feasible, then run the focused test with the usual runtime environment. If the final validation is the full `make test`, that command already gates constraints; do not duplicate the same gate unless earlier feedback would save time.

Handoffs for Fennel-facing feature or bugfix work should include a lightweight constraint-impact note: `helped catch`, `obstructed/noisy`, `changed constraint`, or `not applicable`. Reviewers should verify that constraint validation was reported, or that the report explains why it does not apply. Unresolved `violations`, `fail`, or `interrupted` statuses are validation failures.

When an intentional architecture transition conflicts with a constraint that encodes the old contract, update the production code and the constraint contract together through reviewed changes. Do not contort production code around a stale rule, skip the gate, or add broad baselines/allowlists just to make the gate green. If the new contract is ambiguous, pause for clarification before changing constraints.

CI wiring and runner output verbosity remain deferred follow-ups; this document describes local agent workflow for the existing gate.

## Runner Statuses

The runner reports one of four result statuses:

- `pass` — all required constraints ran and no unaccepted diagnostics remain.
- `violations` — one or more constraints found new, stale, or worsened diagnostics.
- `fail` — a constraint or runner operation failed before producing a valid pass result.
- `interrupted` — a cooperative/CPU-bound Lua constraint run was interrupted.

Every status other than `pass` exits nonzero and blocks the workflow.

## Targets

The Make target is the normal repository workflow. The runner can also be invoked directly for repository, unit-root, app-root, or explicit-file checks:

```bash
./build/space -m constraints.runner:main -- --target repo
./build/space -m constraints.runner:main -- --target unit --root /path/to/unit-root
./build/space -m constraints.runner:main -- --target app --root /path/to/app-scripts
./build/space -m constraints.runner:main -- --target files --file /path/to/one.fnl --file /path/to/two.fnl
```

Use neutral absolute paths for external unit, app, or file targets. Production modules should not import or call constraint modules.

## Constraint Families

The current experimental constraints are grouped into four families:

- **Scene/Sandbox** — protects scene ownership and sandbox boundaries.
- **Lifecycle** — catches stale callback, teardown, drop, and ownership mistakes.
- **Layout/rendering** — checks layout/rendering contracts that are expensive to debug at runtime.
- **Structure/formatting** — keeps Fennel modules within reviewed structural and formatting limits.

These constraints complement human review and normal unit/integration tests; they do not replace either one.

## Baselines

Baselines are reviewed, versioned project data for accepted existing violations. They are not a bypass flag.

A baseline entry records the known exception with its file, rule, current measure, and reason. The gate still blocks when:

- a new violation appears;
- an existing baseline violation worsens;
- a baseline entry becomes stale and no longer matches the current code;
- a required constraint disappears;
- a constraint fails or is interrupted.

When a baseline becomes stale because the code improved, update the reviewed baseline data instead of leaving dead exceptions behind.
