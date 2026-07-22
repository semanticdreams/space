---
type: dev-note
tags:
  - note
---

# Morphs Architecture

This document describes the morph system used to transform one graph node/entity type into another while keeping references stable through identity nodes.

## Goals

- Allow controlled type changes (for example `string-entity -> code-entity`).
- Keep stable references via `identity:*` keys.
- Keep morph logic store/domain-focused and decoupled from graph/view internals.
- Ensure open views (for example notebook/list item previews) refresh immediately after morph.

## Current Scope

- Implemented source type: `string-entity`
- Implemented target type: `code-entity`
- `identity:*` sources are intentionally non-morphable.

## Key Modules

- Morph registry: `assets/lua/morphs/init.fnl`
- String->Code morph: `assets/lua/morphs/string-entity-to-code-entity.fnl`
- Morph UI: `assets/lua/morph-view.fnl`
- Morph launchable: `assets/lua/launchables/morphs.fnl`
- Graph morph adapter: `assets/lua/graph/core.fnl`

Related entity/node modules:

- Code entity store: `assets/lua/entities/code.fnl`
- Code node: `assets/lua/graph/nodes/code-entity.fnl`
- Code node view: `assets/lua/graph/view/views/code-entity.fnl`

## Morph Registry Contract

`Morphs.register(from-scheme, to-scheme, morph-fn, meta)` registers a morph function.

`Morphs.target-items(source-node)` returns available targets for a single source node.

`Morphs.apply(source-node, target, opts)`:

1. Validates source/target.
2. Rejects identity sources.
3. Runs the registered morph function.
4. Emits `morphs.morphed` event.

### `morphs.morphed` payload

The event includes:

- `source-node`
- `source-key`
- `from-scheme`
- `to-scheme`
- `result` (morph-specific structured result)

## String -> Code Morph Behavior

Implemented in `assets/lua/morphs/string-entity-to-code-entity.fnl`.

Given `string-entity:<id>`:

1. Reads source string entity.
2. Creates code entity with:
   - `name = ""`
   - `language = "fnl"`
   - `source = <string value>`
3. Updates all identities whose `target-key` matched old source key to new code key.
4. Deletes the source string entity.
5. Returns result payload fields including:
   - `source-key`
   - `target-key`
   - `target-type`
   - `updated-identity-keys`

Note: this morph function does not mutate graph state directly.

## Graph Adapter (Event-Driven)

`assets/lua/graph/core.fnl` subscribes to `morphs.morphed` and performs graph-side reconciliation:

1. Remove old source node (if present).
2. Load/add target node by key.
3. Emit `graph.node-morphed` with `source-key`, `target-key`, and original payload.

This keeps graph updates outside morph functions.

## Notebook/List View Refresh Behavior

Notebook/list nodes subscribe to both:

- identity store updates (`identity-updated` / `identity-deleted`)
- graph morph completion (`graph.node-morphed`)

Why both:

- Identity update can happen before graph node replacement is fully visible.
- `node-morphed` provides a post-reconciliation refresh point.
- This avoids stale type labels/previews in already-open notebook/list views.

Relevant files:

- `assets/lua/graph/nodes/notebook.fnl`
- `assets/lua/graph/nodes/list-entity.fnl`

## UI Behavior

Morph view (`assets/lua/morph-view.fnl`):

- Reads currently selected graph node (exactly one required).
- Shows morph target search list.
- Applies morph on selection.
- Displays status text for success/failure.

## Testing

Primary tests:

- `assets/lua/tests/test-morphs.fnl`
- `assets/lua/tests/test-notebooks.fnl`
- `assets/lua/tests/test-list-entities.fnl`

Coverage includes:

- target registration and listing
- string->code morph result
- identity target-key retargeting
- source deletion + target creation expectations
- notebook/list edge refresh on identity updates
- notebook/list refresh on `graph.node-morphed`

## Constraints and Decisions

- Identity nodes are non-morphable by design.
- Current language field is unconstrained string; default is `fnl`.
- If source is not wrapped in identity, morph replaces source entity only (no identity auto-creation during morph).

## Next Work

1. Add additional morph targets.
2. Define shared schema for `result` payloads across all morphs.
3. Optionally add dedicated metrics/logging around morph lifecycle events.
4. Add e2e coverage for notebook/list visual update after morph.


## See also

- [Core Platform](/dev/features/core-platform)
