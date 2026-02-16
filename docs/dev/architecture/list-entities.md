# List Entities Implementation Plan

## Overview

List entities allow users to collect graph nodes into ordered lists. Similar to link-entities (which reference two nodes by key), list-entities reference multiple nodes by key and maintain ordering. Users can add, remove, and reorder nodes within a list.

**Color:** Cyan (`glm.vec4 0.0 0.6 0.7 1` / `glm.vec4 0.05 0.65 0.75 1`)

## Architecture

### Components to Create

1. **Storage Layer:** `assets/lua/entities/list.fnl`
2. **Graph Nodes:**
   - `assets/lua/graph/nodes/list-entity.fnl` - Individual list entity node
   - `assets/lua/graph/nodes/list-entity-list.fnl` - List of all list entities
3. **Graph Views:**
   - `assets/lua/graph/view/views/list-entity.fnl` - View for managing a single list
   - `assets/lua/graph/view/views/list-entity-list.fnl` - View for browsing all lists
4. **Integration:**
   - Update `assets/lua/graph/nodes/entities.fnl` - Add `:list` type
   - Update `assets/lua/menu-manager.fnl` - Add "Create List Entity" action
5. **Tests:**
   - `assets/lua/tests/test-list-entities.fnl`
   - `assets/lua/tests/e2e/test-list-entity-view.fnl`

---

## 1. Storage Layer (`assets/lua/entities/list.fnl`)

### Data Structure

```fennel
{:id "uuid"
 :name ""                    ;; Optional user-defined name
 :items ["node-key-1" "node-key-2" "node-key-3"]  ;; Ordered list of node keys
 :created-at 1234567890      ;; Unix timestamp
 :updated-at 1234567890}     ;; Unix timestamp
```

### Persistence

- **Location:** `<user-data-dir>/entities/list/`
- **Format:** JSON files - one file per entity, named `<uuid>.json` (same as link-entities)

### API

```fennel
(fn ListEntityStore [opts])
  ;; opts: {:base-dir optional-path}

  ;; CRUD operations
  :get-entity (fn [self id] ...)
  :create-entity (fn [self opts] ...)   ;; opts: {:name :items}
  :update-entity (fn [self id updates] ...)
  :delete-entity (fn [self id] ...)
  :list-entities (fn [self] ...)        ;; Returns all, sorted by updated-at desc

  ;; List item operations
  :add-item (fn [self id node-key] ...)          ;; Append to end
  :remove-item (fn [self id node-key] ...)       ;; Remove first occurrence
  :reorder-items (fn [self id new-order] ...)    ;; Replace items array
  :move-item (fn [self id from-index to-index] ...) ;; Move item position

  ;; Signals
  :list-entity-created (Signal)
  :list-entity-updated (Signal)
  :list-entity-deleted (Signal)
  :list-entity-items-changed (Signal)   ;; Emits {id, items} on item changes

(fn get-default [opts])  ;; Singleton access
```

### Implementation Notes

- Items are stored as an ordered array of node key strings
- **No duplicates:** `add-item` checks if key already exists and is a no-op if so
- `add-item` appends to end (if not duplicate), emits `list-entity-updated`
- `remove-item` removes first matching key, emits `list-entity-updated`
- `move-item` handles reordering, emits `list-entity-updated`
- All item operations update `updated-at`

---

## 2. ListEntityNode (`assets/lua/graph/nodes/list-entity.fnl`)

### Properties

```fennel
:key entity-id
:label (make-label entity)  ;; Name if set, else entity-id
:color CYAN
:sub-color CYAN_ACCENT
:size 8.0
:view ListEntityNodeView
```

### Methods

```fennel
:get-entity (fn [self] ...)
:update-name (fn [self new-name] ...)
:add-item (fn [self node-key] ...)
:remove-item (fn [self node-key] ...)
:move-item (fn [self from-index to-index] ...)
:delete-entity (fn [self] ...)
:refresh-label (fn [self] ...)

;; Graph node creation for list items
:add-item-nodes (fn [self] ...)  ;; Add existing nodes from items to graph as edges
```

### Signals

```fennel
:entity-deleted (Signal)
:items-changed (Signal)    ;; Proxies store's list-entity-items-changed for this entity
```

### Signal Connections

- Listen to `store.list-entity-updated` -> `refresh-label`
- Listen to `store.list-entity-deleted` -> emit `entity-deleted`, remove from graph
- Listen to `store.list-entity-items-changed` -> emit `items-changed` if matching id
- Attach membership edges via graph lifecycle (see “Problems Encountered”)

---

## 3. ListEntityListNode (`assets/lua/graph/nodes/list-entity-list.fnl`)

### Properties

```fennel
:key "list-entity-list"
:label "list entities"
:color CYAN
:sub-color CYAN_ACCENT
:size 8.0
:view ListEntityListNodeView
```

### Methods

```fennel
:collect-items (fn [self] ...)     ;; Returns [[entity, label], ...]
:emit-items (fn [self] ...)
:add-entity-node (fn [self entity] ...)  ;; Add ListEntityNode as edge target
:create-entity (fn [self opts] ...)
```

### Signals

```fennel
:items-changed (Signal)
```

---

## 4. ListEntityNodeView (`assets/lua/graph/view/views/list-entity.fnl`)

### UI Layout

```
┌─────────────────────────────────────────────────┐
│ [Name Input                              ]      │
├─────────────────────────────────────────────────┤
│ Items (3):                                      │
│ ┌─────────────────────────────────────────────┐ │
│ │ [node-key-alpha]     [↑] [↓] [×]            │ │
│ │ [node-key-beta]      [↑] [↓] [×]            │ │
│ │ [node-key-gamma]     [↑] [↓] [×]            │ │
│ └─────────────────────────────────────────────┘ │
├─────────────────────────────────────────────────┤
│ [+ Add Selected] [Delete List]                  │
└─────────────────────────────────────────────────┘
```

### Components

1. **Name Input** - Text input for list name, updates via `node:update-name`
2. **Items List** - Scrollable list of items with:
   - **Item button** (truncated node key) - clicking focuses the node in the graph
   - Move up button (↑) - disabled for first item
   - Move down button (↓) - disabled for last item
   - Remove button (×)
3. **Action Row:**
   - "Add Selected" button - adds all currently selected nodes to the list (duplicates are ignored)
   - "Delete" button - deletes the entire list entity

### Selection Integration

The "Add Selected" button reads from `app.graph-view.selection.selected-nodes` and calls `node:add-item(key)` for each selected node. Duplicates are silently ignored (no-op).

### Focus Node on Click

When clicking an item button:
1. Look up node via `app.graph:lookup(key)`
2. If node exists, get its focus-node from `app.graph-view.focus-nodes[node]`
3. Call `focus-node:request-focus()` to focus it

If the node is not currently in the graph, the click does nothing (the node may have been removed). In the future, this could be extended to add the node to the graph if it doesn't exist.

### Signal Connections

- Listen to `node.items-changed` -> rebuild items list UI

---

## 5. ListEntityListNodeView (`assets/lua/graph/view/views/list-entity-list.fnl`)

### UI Layout

```
┌──────────────────────────────────────┐
│ [Create]                             │
├──────────────────────────────────────┤
│ SearchView with list entities        │
│ - My List (5 items)                  │
│ - Todo Items (12 items)              │
│ - ...                                │
└──────────────────────────────────────┘
```

### Components

1. **Create Button** - Creates new empty list entity and adds node to graph
2. **SearchView** - Paginated list of all list entities
   - Each item is a button showing name (or item count)
   - Clicking adds ListEntityNode to graph

### Signal Connections

- Listen to `node.items-changed` -> refresh list

---

## 6. Integration Updates

### `assets/lua/graph/nodes/entities.fnl`

Add list type to `collect-types`:

```fennel
(fn collect-types [_self]
  (local produced [])
  (table.insert produced [:string "string"])
  (table.insert produced [:link "link"])
  (table.insert produced [:list "list"])  ;; NEW
  produced)
```

Add list handling to `add-type-node`:

```fennel
(= type-key :list)
(do
  (local list-node (ListEntityListNode {}))
  (graph:add-edge (GraphEdge {:source self
                              :target list-node})))
```

Import at top:
```fennel
(local ListEntityListNode (require :graph/nodes/list-entity-list))
```

### `assets/lua/menu-manager.fnl`

Add new action to `default-root-actions`:

```fennel
(table.insert actions
              {:name "Create List Entity"
               :icon "playlist_add"
               :fn (fn [_button _event]
                     (local ListEntityStore (require :entities/list))
                     (local store (ListEntityStore.get-default))
                     (local selected (or (and app.graph-view
                                              app.graph-view.selection
                                              app.graph-view.selection.selected-nodes)
                                         []))
                     ;; Collect keys from selected nodes
                     (local items
                       (icollect [_ node (ipairs selected)]
                         (when node.key node.key)))
                     (local entity (store:create-entity {:items items}))
                     (when (and app.graph entity)
                       (local ListEntityNode (require :graph/nodes/list-entity))
                       (local node (ListEntityNode {:entity-id entity.id
                                                    :store store}))
                       (app.graph:add-node node)))})
```

---

## 7. Tests (`assets/lua/tests/test-list-entities.fnl`)

### Store Tests

- `list-entity-store-creates-entities` - Create with name and items
- `list-entity-store-retrieves-entities`
- `list-entity-store-updates-entities` - Update name
- `list-entity-store-deletes-entities`
- `list-entity-store-lists-entities` - Sorted by updated-at
- `list-entity-store-emits-created-signal`
- `list-entity-store-emits-updated-signal`
- `list-entity-store-emits-deleted-signal`
- `list-entity-store-adds-items` - Test add-item
- `list-entity-store-removes-items` - Test remove-item
- `list-entity-store-moves-items` - Test move-item
- `list-entity-store-emits-items-changed-signal`

### Node Tests

- `list-entity-node-loads`
- `list-entity-node-creates-with-correct-properties`
- `list-entity-list-node-loads`
- `list-entity-list-node-creates-with-correct-properties`

### View Tests

- `list-entity-node-view-loads`
- `list-entity-list-node-view-loads`

### Integration Tests

- `entities-node-includes-list-type`

### E2E Snapshot Test (`assets/lua/tests/e2e/test-list-entity-view.fnl`)

- Render ListEntityNodeView with sample items
- Snapshot to `assets/lua/tests/data/snapshots/list-entity-view.png`

---

## 8. File Summary

### Files to Create

| File | Description |
|------|-------------|
| `assets/lua/entities/list.fnl` | Storage layer with CRUD + item operations |
| `assets/lua/graph/nodes/list-entity.fnl` | Individual list entity graph node |
| `assets/lua/graph/nodes/list-entity-list.fnl` | List browser graph node |
| `assets/lua/graph/view/views/list-entity.fnl` | Single list management view |
| `assets/lua/graph/view/views/list-entity-list.fnl` | List browser view |
| `assets/lua/tests/test-list-entities.fnl` | Unit tests |
| `assets/lua/tests/e2e/test-list-entity-view.fnl` | E2E snapshot test |

### Files to Modify

| File | Changes |
|------|---------|
| `assets/lua/graph/core.fnl` | Add optional `node:added(graph)` lifecycle hook (post-insert) |
| `assets/lua/graph/nodes/entities.fnl` | Add `:list` type, import ListEntityListNode |
| `assets/lua/menu-manager.fnl` | Add "Create List Entity" action |
| `assets/lua/tests/fast.fnl` | Add test-list-entities to test suite |
| `assets/lua/tests/e2e.fnl` | Add test-list-entity-view to E2E suite |

---

## 9. Implementation Order

1. **Storage layer** (`entities/list.fnl`) - Foundation, can be tested independently
2. **ListEntityNode** (`graph/nodes/list-entity.fnl`) - Depends on storage
3. **ListEntityListNode** (`graph/nodes/list-entity-list.fnl`) - Depends on storage and ListEntityNode
4. **ListEntityNodeView** (`graph/view/views/list-entity.fnl`) - Depends on node
5. **ListEntityListNodeView** (`graph/view/views/list-entity-list.fnl`) - Depends on list node
6. **Integration** - Update entities.fnl and menu-manager.fnl
7. **Tests** - Unit tests and E2E tests
8. **Verification** - Run full test suite

---

## 10. Verification

Run the full test suite:
```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
```

Run E2E tests:
```bash
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test-e2e
```

Manual verification:
1. Start the app with `make run`
2. Right-click to open context menu
3. Select "Create List Entity" - should create empty list or list with selected nodes
4. Double-click the list entity node to open view
5. Add/remove/reorder items in the view
6. Verify changes persist after restart

---

## 11. Problems Encountered (and Resolutions)

### A) C stack overflow / recursion when adding list entity nodes

**Symptom:** Creating a list entity (especially from the root context menu with selected nodes) could crash with `C stack overflow`, with repeated recursion through:

- `ListEntityNode:add-item-nodes`
- `ListEntityNode:mount`
- `Graph:add-node` / `Graph:add-edge`

**Root cause:** `Graph.add-node` mounts the node before inserting it into `graph.nodes`. If `mount` calls `graph:add-edge`, `graph:add-edge` calls `graph:add-node` for the edge endpoints. Since the source node is not in `graph.nodes` yet, it re-enters `mount` and loops forever.

**Resolution:** Introduce an explicit post-add lifecycle hook:

- `Graph.add-node` calls optional `node:added(graph)` after it inserts the node and emits `node-added`.
- `ListEntityNode` uses `added` to create membership edges to any items that already exist in the graph.
- `ListEntityNode` also listens to `graph.node-added` to attach membership edges when item nodes are added later.

This keeps `mount` side-effect-free with respect to graph mutations and makes the lifecycle ordering explicit for any future nodes that need to react to being inserted.

### B) E2E snapshot golden creation and environment constraints

**Symptom:** When the snapshot golden didn’t exist yet, snapshot runs could fail before update logic ran, and E2E runs could fail in restricted environments with SDL/X11 errors.

**Resolution:**

- E2E snapshots require an environment that can start SDL + GL under Xvfb (or equivalent). `make test-e2e` already uses `xvfb-run`.
- To create/update the list entity golden:

```bash
SPACE_SNAPSHOT_UPDATE=list-entity-view make test-e2e
```

- For “does the golden exist?” checks, prefer a direct filesystem path derived from `SPACE_ASSETS_PATH` so missing goldens don’t fail asset lookup before `SPACE_SNAPSHOT_UPDATE` can create them.
