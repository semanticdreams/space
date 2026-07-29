# Retrospective Devlog Backfill Design

## Purpose

The project history should read as a continuous devlog rather than a few isolated journal entries. The goal is to retroactively add monthly-ish, source-grounded entries for known historical arcs using repository documentation and commit history, without pretending to know exact daily work that was never journaled.

## Direction

Use a one-time curated content pass, not an automation pipeline. The existing daily devlog automation remains forward-looking; this backfill fills historical gaps with a small set of phase/month anchor entries where the known documentation supports a meaningful narrative. Dates may be approximate anchors when the known history is phase-based, but the prose must make the work read as an arc or “by this point” milestone instead of claiming exact same-day completion.

Monthly-ish granularity is preferred over daily reconstruction. Daily backfill would turn the devlog into commit-history prose and would require inventing context for periods where work happened on branches or was later documented in bulk. Phase-only entries would be safest but too sparse. The middle ground is to create entries for the major missing arcs between existing journal dates, stretching dates only where that produces a truthful and readable history.

## Source Material

Backfill entries may use only evidence from the repository:

- existing journal entries in `docs/dev/journal/`;
- `docs/dev/project/history.md`, which summarizes project phases from 2025-07 through 2026-07;
- relevant ADRs, feature pages, project milestones, subsystem pages, and notes under `docs/dev/`;
- commit history for date sanity checks and topic confirmation.

The content must not invent ungrounded features, outcomes, authors, motivations, or dates. If the available sources cannot support a proposed entry, skip it rather than filling every calendar month.

## Entry Set

Preserve existing non-empty 2025-09 and 2026-02 journal/devlog entries. Add or update only the gaps that are supported by known history:

- `2025-10-01.md` — a quiet long-lived Lua/Fennel branch migration arc spanning late 2025 into early 2026, based on the Lua branch ADR and project history.
- `2026-03-18.md` — fill the existing empty stub with the March world-building arc: terrain, graph editing, world entities, lighting, and graph exposure.
- `2026-04-16.md` — stabilization arc: lifecycle ownership, signal cleanup, composable states, stylus drawing, Yojimbo, and canvas modes.
- `2026-05-08.md` — agent/live-development arc: agent runner, presets, MCP transport, OpenCode streaming, reloadable units, and user-code scanning.
- `2026-06-15.md` — cross-platform arc: Windows cross-compilation, board canvas mode, packaging maturation, distro smoke tests, and hot-reload cache cleanup.
- `2026-07-14.md` — convert the existing knowledge-base bootstrap entry into a devlog entry that also situates panel transfer, repository workbench, and conversation-first supervisor work.

This set intentionally leaves some calendar months without entries when the source material supports only a broad branch arc or an already-covered migration cluster.

## Writing Contract

Each new or rewritten backfill entry uses the daily devlog entry shape:

```md
---
type: journal
tags: [journal, devlog]
created: YYYY-MM-DD
---

# YYYY-MM-DD

One short narrative paragraph.
```

The paragraph should be brief, narrative, and contextual. It should explain how the known work moved Space toward its larger goals: replacing the Python prototype, making the graph a universal interface, stabilizing world-building, adding live agent workflows, hardening cross-platform delivery, or improving development operations. It must not include `## Today`, `## Decisions`, `## Tomorrow`, bullet lists, commit hashes, author lists, raw file lists, or a chronological commit summary.

## Data Flow

The implementer reads the approved source documents, drafts the selected entries, validates the entry shape with a focused script or inline check, regenerates `docs/dev/journal/index.md` and `docs/dev/devlog.md` with `npm run devlog:indices`, and runs docs validation. The reviewer checks both markdown shape and historical restraint: every claim should be traceable to known repo docs or commit history.

## Error Handling

If source review contradicts the proposed entry set or an entry would require speculation, the implementer should stop with `NEEDS_CONTEXT` instead of fabricating a paragraph. If docs generation or build fails, debug the failure separately and do not hide it by editing generated output by hand.

## Validation

- Focused entry-shape validation for all new or rewritten retrospective entries.
- Regenerate indexes with `cd docs && npm run devlog:indices`.
- Run `cd docs && npm run test:scripts`.
- Run `cd docs && npm run docs:build`.
- Run `git diff --check`.
- Review the final diff to ensure existing non-empty 2025-09 and 2026-02 entries remain unchanged and the backfill reads as narrative history, not commit history.

## Acceptance Criteria

- The backfill creates or updates the selected monthly-ish entries only where source material supports them.
- Existing non-empty historical journal entries are preserved.
- The empty `2026-03-18.md` stub is filled or, if contradicted by source review, left with an explicit blocker.
- `2026-07-14.md` is converted to the one-paragraph devlog contract and tagged for devlog publication.
- Generated journal and devlog indexes are up to date.
- The final docs build and script tests pass.
