# Workflow Preview Decomposition Design

## Purpose

Workflow definition previews have become crowded because they combine summary,
controls, step browsing, run browsing, and bulk reveal behavior in one card. The
graph should make workflows easy to inspect without hiding related objects or
auto-expanding the map. This change decomposes the preview into focused graph
surfaces.

## Decision

Use a compact workflow definition preview plus dedicated explorer nodes:

- `workflow-definition:<id>` preview becomes a control card with concise summary
  and primary actions: **Start**, **New Step**, **Open Steps**, and **Open Runs**.
- `workflow-step-explorer:<id>` owns step browsing and step bulk reveal. The
  definition preview no longer exposes embedded step search or **Reveal All
  Steps**.
- Add `workflow-run-explorer:<id>` to own run browsing for a workflow definition.
  Selecting a run from this node explicitly materializes one
  `workflow-run:<run-id>` node in the active graph map.

## Alternatives Considered

1. Remove only step browsing from the definition preview and keep run browsing
   inline. This is smaller, but leaves the preview crowded and creates an
   inconsistent steps-vs-runs model.
2. Move both steps and runs to dedicated explorer nodes. This is the selected
   approach because it gives each node one clear job and keeps graph expansion
   explicit.
3. Add a generic workflow details node. This was rejected because it recreates a
   broad details bucket instead of using focused graph nodes.

## Architecture

`WorkflowStore` remains the owner of workflow definitions, steps, runs, run
steps, and events. Graph nodes adapt store records into visible graph objects.
`GraphMap` owns map-local materialized topology only.

The workflow definition node remains the entry/control point for a workflow. The
step explorer and run explorer are UX-purpose graph nodes linked explicitly from
the definition node when the user chooses **Open Steps** or **Open Runs**. No
related steps, runs, or run events are materialized implicitly.

## Components

- Workflow definition node/preview:
  - expose summary counts and latest-run status;
  - preserve existing start/new-step behavior;
  - open the step explorer;
  - open the new run explorer;
  - remove embedded step/run search controls.
- Step explorer:
  - continue listing/searching steps for one definition;
  - move **Reveal All Steps** here.
- Run explorer:
  - list/search runs for one definition;
  - validate selected runs belong to that definition;
  - materialize selected run nodes explicitly and map-locally.

## Error Handling

Missing stores, definitions, graph maps, key loaders, or foreign-definition
records should fail loudly. Failed graph materialization must not leave stale
topology behind. Blank or missing workflow data should show clear zero-count
summaries rather than silently hiding broken behavior.

## Testing

Focused workflow graph tests should cover:

- compact definition preview fields and absence of embedded step/run searches;
- **Open Steps** materializing the step explorer;
- step explorer owning **Reveal All Steps**;
- run explorer key loading, scoped run listing, selection materialization, and
  foreign-run rejection;
- lifecycle cleanup for preview widgets and listeners;
- action-boundary failures for missing loaders and no stale topology.

Validation order for Fennel/UI work remains compile check, constraints, focused
workflow graph tests, then broader tests if loader registration risk warrants it.
