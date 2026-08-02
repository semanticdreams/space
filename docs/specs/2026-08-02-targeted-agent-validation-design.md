# Targeted Agent Validation Design

## Goal

Make Space/OpenCode agentic development faster by moving task-level local validation from full build/test by default to targeted local validation by default, while preserving integration safety through PR CI and explicit high-risk escalation.

## Context

Full local validation in every task worktree is expensive and slows agent throughput. The repository already has focused validation primitives: touched-file Fennel compile checks, explicit-file constraints, focused Fennel test modules, `TEST_FILTER`, and focused CTest targets. Incremental `make build` is usually fast and remains necessary whenever Fennel validation needs a usable `./build/space` runtime or C++/CMake/runtime inputs changed.

Space often exercises C++ behavior through Lua/Fennel bindings, so validation scope must be chosen by behavioral surface, not by file extension alone.

## Chosen Design

Update agent and workflow instructions to use a local validation ladder:

1. Run the narrowest meaningful checks during implementation.
2. Keep `make build` as the normal freshness/runtime prerequisite when `./build/space` may be missing or stale.
3. Choose behavioral tests by the surface that users and callers exercise:
   - Fennel/UI/layout behavior: Fennel compile check, constraints, focused Fennel tests.
   - C++ behind Fennel bindings: build, then focused Fennel tests through the binding surface.
   - Pure C++ utility behavior: build the relevant target and/or focused CTest.
   - Docs/prompt-only changes: focused text, diff, and formatting checks.
   - Build, package, startup, runtime initialization, or broad binding/API changes: broader local validation remains appropriate.
4. Before task checkpoint commits, require sufficient focused validation plus a short explanation of coverage, not full `make test` by default.
5. Treat PR CI as the authoritative full build/test/e2e integration gate. Do not claim final completion or ready-to-merge until the applicable integration gate is green.

## Components To Update

- `AGENTS.md`: repository validation guidance and commit convention text.
- `.opencode/agents/implementer.md`: implementer validation expectations and report contents.
- `.opencode/agents/reviewer.md`: reviewer validation-review criteria.
- `.opencode/agents/planner.md`: plan validation ladder expectations.
- `.opencode/skills/subagent-driven-development/SKILL.md`: implementer handoff/report expectations and finish handoff semantics.
- `.opencode/skills/finishing-a-development-branch/SKILL.md`: final integration validation should account for targeted local validation plus PR CI, while retaining full local validation for high-risk cases when required.
- Optionally `docs/dev/features/development-tooling.md`: document the workflow assumption if the prompt changes need a canonical docs/dev reference.

## Non-Goals

- Do not change production runtime code, tests, Makefile targets, CI workflows, or repository workbench check implementations in this pass.
- Do not skip Fennel constraints; targeted validation may call constraints directly through `./build/space`, but constraints remain part of Fennel-facing validation.
- Do not pretend Fennel can run without a built Space runtime.
- Do not make local targeted validation a substitute for the full PR integration gate.

## Error Handling And Safety

- If targeted validation fails, agents must debug and fix through the existing systematic-debugging and implementer/reviewer loops.
- If a task changes high-risk surfaces or the reviewer identifies under-covered risk, broaden local validation before proceeding.
- If CI fails after PR creation, the failure is active work: diagnose, route fixes through implementer/reviewer, and rerun the relevant checks.

## Testing

Because this is workflow/prompt documentation, validation is focused instruction validation:

- exact-text searches for the new targeted-validation policy;
- checks that old unconditional “full suite before every commit” language is removed or scoped;
- `git diff --check`;
- reviewer verification of instruction consistency.

Full product tests are not required for this prompt/docs-only change.
