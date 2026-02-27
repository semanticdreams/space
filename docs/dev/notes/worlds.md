# Worlds

This note describes the current world architecture in `assets/lua` and the intended design boundaries.

## Goals

- Support multiple worlds as browser-like tabs.
- Keep engine/window/HUD app-owned.
- Keep camera/scene/graph world-owned.
- Allow lazy world startup and world-controlled lifecycle behavior.
- Persist world registry and per-world state under user data.

## Ownership Model

### App-owned

- Engine and window lifecycle (`main.fnl`).
- Input routing and global shortcuts.
- HUD shell/layout and global HUD controls.
- World registry, active world selection, tab creation/close.

### World-owned

- Camera.
- Scene and world-local runtime systems.
- Graph + GraphView + object selector.
- World-local persistence decisions (currently `home` persists camera state).

## Core Modules

- `assets/lua/world-manager.fnl`
  - Manages tab list, active world, lazy instance creation.
  - Persists world index at `.../worlds/index.json`.
  - Handles activation/deactivation/suspend/drop transitions.
- `assets/lua/home-world.fnl`
  - Default world type.
  - Loads/saves state in `.../worlds/<world-id>/world.json`.
  - Builds world runtime (camera, scene, graph, graph-view).
- `assets/lua/world-tabs-widget.fnl`
  - Tab strip UI (`home`, `home-2`, ...) + `+` button.

## Lifecycle

World interface (implemented by `HomeWorld`):

- `init(ctx)`: one-time setup, load persisted state.
- `activate(ctx)`: become active; build runtime if needed.
- `deactivate(ctx, reason)`: become inactive; lightweight transition.
- `suspend(ctx)`: free heavy runtime resources while tab stays open.
- `resume(ctx)`: reactivate from suspended state.
- `drop(ctx, reason)`: final cleanup and persistence.
- `update(delta, opts)`: per-frame hook (active/inactive flag via `opts`).
- `get-runtime()`: returns currently mounted runtime.
- `get-hud-contrib()`: returns optional world HUD contributions.

### Current behavior

- `deactivate` is lightweight.
- `suspend` is delayed (default 3000 ms inactivity) and clears runtime.
- `drop` also clears runtime and persists state.

## HUD Contribution Contract

HUD is always app-owned. Worlds contribute declaratively through slots.

Expected `get-hud-contrib()` shape:

- `:control_panel_body` -> builder (optional)
- `:status_panel_body` -> builder (optional)
- `:overlay` -> builder (optional)

App behavior on active-world switch:

1. Bind new active world runtime.
2. Rebuild HUD with active world slot builders.
3. Mount overlay contribution (if present).
4. Unmount old world overlay/contrib atomically.

Tab strip remains app-owned and mounted in the control panel status area.

## Persistence

Under `appdirs.user-data-dir("space")`:

- `worlds/index.json`
  - List of worlds (`id`, `type`, `name`).
- `worlds/<world-id>/world.json`
  - Per-world persisted data.

Current `home` world persists:

- camera transform
- graph topology and open node views
- scene persisted panels
- HUD persisted panels

## Startup and Switching

- On app init:
  - world manager loads world index.
  - if empty, creates one default `home`.
  - activates first world.
- Creating world:
  - adds world record, creates directory, optionally activates immediately.
- Closing world:
  - drops world, removes from index.
  - if last world closes, app exits (`engine.quit`), browser-style.

## Global Shortcuts

Handled at app level:

- `Ctrl+Tab`: next world.
- `Ctrl+Shift+Tab`: previous world.
- `Ctrl+W`: close active world.
- `Alt+1..9`: activate tab by index.

Conflict policy:

- If an input widget has active focus and one of these shortcuts is pressed, code errors intentionally (fail fast).

## Persistence Failure Policy

- World index (`worlds/index.json`) load/parse failures are fatal errors.
- Home world state (`worlds/<id>/world.json`) load/parse failures are fatal errors.
- HUD capture is strict: every open HUD panel must declare persistence metadata (`:kind`), otherwise capture errors.
- HUD capture is also strict about restore strategy: a persisted panel kind must either:
  - have a registered runtime restorer (used for dynamic world-bound kinds like graph node views), or
  - declare `:restorer-module` in persistence metadata.
- HUD restore is strict: if neither strategy is available, restore errors.
- Preferred ownership: `:restorer-module` should point to the feature module that owns that panel kind
  (for example `launchables/launcher`, `launchables/chat`, `graph/view/views/fs-ripgrep-dialog`)
  rather than a generic central restorer table.

## Design Rules

- Worlds should not imperatively mutate HUD structure directly for persistent UI.
  - Use `get-hud-contrib` slot builders instead.
- Keep cross-world state minimal and explicit.
- Share asset caches at app level; keep mutable runtime objects world-local.
- Use world lifecycle hooks for resource policy instead of app-side special cases.

## Known v1 Limits

- Only `home` world type exists.
- Persistence requires explicit panel metadata/restorers for dialog-style panels.
- No rename/reorder UI yet.
- No autosave yet (save is guaranteed on world drop/app drop).

## Future: Module Identity

Current persisted HUD panel records use `:restorer-module` path strings for restore.

Planned direction (not implemented yet):

- Support hash-based restorer identity (for example `:restorer-hash`) so panel restore can resolve
  modules from a verified local/remote module cache.
- During migration, resolver should prefer hash identity when present and fall back to module path.
- Keep failure policy strict: unresolved or unverifiable restorers should still fail loudly.
