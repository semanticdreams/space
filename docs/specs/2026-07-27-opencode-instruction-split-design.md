# OpenCode Instruction Split Design

## Purpose

Humpback now has a project-local `.opencode/` configuration, so project guidance no longer needs to live entirely in `AGENTS.md`. The goal is to keep always-on context compact while preserving strong project doctrine for agents that work on Fennel widgets, graph exposure, lifecycle/teardown, tests, and release workflow.

## Direction

Use a balanced split:

- `AGENTS.md` remains the concise, durable source of project facts that every agent and tool should see: repository structure, canonical build/test commands, branch/integration policy, high-risk project rules, and pointers to deeper docs.
- `.opencode/agents/**` remains mostly role and permission configuration: supervisor coordination, implementer/reviewer discipline, model choices, and safe tool behavior.
- `.opencode/skills/**` gains project-specific, task-triggered guidance for Humpback domains that are too detailed to keep always loaded.
- `docs/dev/**` remains the human-readable canonical architecture reference. Project skills should reference docs instead of copying long sections.

## Proposed Project Skills

Create project-specific skills only where triggerable context is useful:

1. `humpback-fennel-ui`
   - Use when editing or designing Fennel widgets, layout, rendering adapters, interaction widgets, or widget tests.
   - Points to `docs/dev/fennel/style.md`, `docs/dev/lifecycle-invariants.md`, and `docs/dev/widget-ownership-and-teardown.md`.
   - Captures compact reminders: builder closures, explicit `Layout` ownership, dirt rules, direct child transform writes during layout passes, `drop` responsibility, no silent fallbacks, and Fennel idioms.

2. `humpback-graph-doctrine`
   - Use when editing graph nodes, graph maps, graph views, graph persistence/topology, or graph terminology.
   - Points to `docs/dev/notes/graph.md` and `docs/dev/graph-maps.md`.
   - Captures compact reminders: graph as exposure/adaptor layer, graph topology vs domain-owned data, key loaders adapt owning stores, and forbidden terminology.

3. `humpback-testing-runtime`
   - Use when running or adding Humpback tests, E2E snapshots, remote-control debugging, profiling, or build/test harnesses.
   - Keeps project command details discoverable without bloating generic process skills.
   - Points back to `AGENTS.md` for canonical commands and to relevant docs when present.

Do not create a separate skill for every subsystem yet. Add skills when there is a recurring task trigger and enough domain-specific instruction to justify progressive loading.

## AGENTS.md Reshape

Trim `AGENTS.md` by moving long domain-specific implementation details into short summaries plus references to the new project skills and canonical docs. Keep these sections always-on:

- urgency/quality expectations and branch convention;
- project structure and historical-source caveats;
- canonical build, test, run, and timeout commands;
- essential no-silent-failure/no-fallback rules;
- commit convention and PR integration policy;
- pointers to project skills for Fennel UI, graph doctrine, and testing/runtime workflows.

Avoid removing facts that non-OpenCode tools still need. `AGENTS.md` should remain useful outside OpenCode, but it should not duplicate full docs/dev pages or long skill bodies.

## Agent Changes

Keep role agents generic by default. Add only small project-aware routing guidance where it improves behavior:

- Supervisor: when a request touches Fennel UI/layout, graph topology/exposure, or Humpback testing/runtime, invoke the corresponding project skill before planning or implementation.
- Planner: require plans that change behavior, architecture, workflows, or operational assumptions to update the appropriate `docs/dev` page.
- Implementer and reviewer: rely on task briefs and invoked skills rather than permanently embedding all Humpback architecture rules.

Do not create new subagents initially. The existing explorer/planner/implementer/reviewer/adjudicator/debug-advisor roles are enough. Consider a specialized subagent later only if repeated work shows a stable, role-specific need that a skill cannot cover.

## Safety and Maintenance Rules

- Prefer references to `docs/dev/**` over copying full architecture documents into skills.
- If guidance exists in both `AGENTS.md` and a skill, one should be a short pointer and the other should hold the actionable detail.
- Project skills must have precise descriptions so they trigger only on relevant tasks.
- Config changes under `.opencode/**` still go through implementer → reviewer → pass.
- After `.opencode` changes, users must restart OpenCode for the new config to load.

## Acceptance Criteria

- `AGENTS.md` is shorter and primarily contains always-on project facts plus pointers.
- Project-specific `.opencode/skills` exist for Fennel UI, graph doctrine, and testing/runtime guidance.
- The new skills reference canonical docs and avoid long duplicated content.
- Supervisor routing guidance makes those skills discoverable.
- No production or test code changes are required.
- Existing OpenCode workflow agents remain valid and safe.
