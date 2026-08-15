# Explicit Graph Discovery Design

## Summary

The graph should have one discovery/materialization model: explicit node
previews/views/actions. The old node relationship hook named `get-edges` creates
hidden fan-out behavior, competes with preview buttons/search lists, and made
migrated workflow-backed sessions appear broken because Workflows root could dump
both definitions and runs without a clear user-chosen hierarchy.

This design removes that hook and the graph trigger APIs that existed only to
materialize it. Nodes should expose domain relationships through user-facing
controls that let the user choose exactly what to add to the current `GraphMap`.

## Goals

- Remove `get-edges` from graph production code and focused tests.
- Remove graph `trigger` APIs whose sole behavior is to call node relationship
  hooks and bulk-add edges.
- Make workflow browsing explicit and hierarchical:
  - `Workflows` root browses/searches workflow definitions only.
  - A workflow definition browses/searches its own runs.
  - Workflow steps expose their code through `Show Code`.
  - Workflow runs expose details/steps/events through explicit run controls.
- Prevent root-level fan-out of all workflow runs.
- Preserve graph doctrine: stores own domain records; graph map topology records
  only user-materialized visible nodes/edges.
- Provide tests that fail if the old relationship hook or graph trigger path is
  reintroduced.

## Non-Goals

- No new automatic graph expansion behavior.
- No global graph search redesign beyond workflow browsing needed for this
  cleanup.
- No performance cache for workflow lists; use store listing and preview-side
  search/filtering for now.
- No changes to non-graph timer/debouncer code that happens to use ordinary
  words like “trigger”; this cleanup is about the graph relationship hook and
  graph trigger APIs.

## Current Problem

Most graph UX already uses explicit controls: Start rows select one target,
Notebook and LLM list views open one selected item, workflow step previews expose
`Show Code`, and workflow runs expose detail controls.

Workflow nodes were the exception. They implemented a hidden relationship hook
that returned GraphEdge objects and graph `trigger` methods that materialized
those edges. The hook lived mostly in workflow nodes and had tests, but it was
not a clear user operation. The result was two competing discovery mechanisms:

1. explicit preview/search/action controls; and
2. hidden bulk relationship expansion.

The Workflows root hotfix exposed this conflict: one button loaded definitions
and runs together, while the desired mental model is Workflows root -> workflow
definition -> workflow run.

## Chosen Architecture

### Single Discovery Mechanism

Graph materialization is explicit. A node preview or view presents searchable
rows/buttons and the user picks what to add. Those controls call node methods
that load graph-addressable keys through the current graph map and add visible
edges.

There is no fallback relationship hook that silently supplies edges.

### Workflow Hierarchy

The workflow browse path becomes:

```text
Workflows root
  -> selected workflow-definition:<definition-id>
       -> selected workflow-run:<run-id>
            -> selected/details run-step and run-event nodes
```

The root may show counts and a search list of definitions, but it must not load
or list runs directly. A workflow definition preview may show counts and a search
list of runs for that definition. Selecting a run loads only that run and adds a
definition -> run edge.

### Graph API Cleanup

The base graph node no longer installs a default relationship hook. Graph core
and graph map no longer expose the graph trigger methods that call that hook.
Tests should use explicit node methods/actions instead of calling the hook.

If a future feature needs non-materializing relationship metadata, it should use
a new name and a new design that clearly separates “relationship exists” from
“user chose to add this node to the visible graph.”

## User Experience

- Opening `Workflows` shows `New Workflow`, workflow definition count, and a
  searchable list of definitions.
- Selecting one workflow definition from that search list loads only that
  definition node and an edge from Workflows root to it.
- Opening a workflow definition shows existing controls (`Start`, `New Step`) and
  a searchable list/count of runs for that definition.
- Selecting one run loads only that run node and an edge from the definition to
  it.
- Opening a workflow run keeps the explicit details affordance for run steps and
  events; it must not rely on the removed relationship hook.

## Testing Strategy

- Add/modify workflow graph tests so Workflows root search loads only selected
  definitions and never root-level runs.
- Add/modify workflow definition preview tests so run search loads only selected
  runs for that definition.
- Update run detail tests so explicit run controls materialize steps/events
  without relationship-hook calls.
- Add a repository-level focused assertion that graph production/test files no
  longer contain the removed hook name or graph trigger materialization API.
- Run Fennel compile check, constraints, focused workflow graph tests, and a
  broader relevant graph/workflow test if required by review.

## Acceptance Criteria

- No `get-edges` hook remains in graph production code or focused graph tests.
- Graph core/map no longer expose trigger methods whose purpose is materializing
  node relationship hooks.
- Workflows root browse/search materializes definitions only.
- Workflow definition browse/search materializes runs for that definition only.
- Workflow run detail materialization remains available through explicit user
  controls.
- Existing creation actions (`New Workflow`, `New Step`, `Show Code`, `Start`) keep
  working.
- Missing graph dependencies still fail loudly at action boundaries.
