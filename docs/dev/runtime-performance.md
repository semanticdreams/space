# Runtime Performance Modes

This document describes the runtime performance system used by the app, including design goals, settings, mode resolution, implementation details, usage APIs, and trade-offs.

## Goals

- Keep foreground UX responsive.
- Reduce unnecessary work in background/minimized states.
- Allow explicit user intent (`manual` vs `auto`).
- Keep policy/data in settings and execution in one resolver.
- Support expensive workloads without starving other processes.

## High-level Model

Runtime performance has:

- `control_mode`: top-level behavior switch.
- `manual_mode`: user baseline preference.
- `effective_mode`: mode currently applied after evaluating rules/overrides.

Control modes:

- `manual`: always use `manual_mode`; automatic rules are ignored.
- `auto`: evaluate automatic rules + leases; if none apply, fall back to `manual_mode`.

Supported modes:

- `max`
- `balanced`
- `unfocused`
- `minimized`

Each mode has policy fields:

- `fps_cap`
- `pause_physics`
- `pause_input`

## Settings Schema

Path root: `runtime_performance`

```toml
[runtime_performance]
control_mode = "auto"              # "manual" | "auto"
manual_mode = "max"                # baseline when manual, or auto fallback
restore_manual_on_clear = true      # if no override is active in auto mode

[runtime_performance.modes.max]
fps_cap = 60
pause_physics = false
pause_input = false

[runtime_performance.modes.balanced]
fps_cap = 30
pause_physics = false
pause_input = false

[runtime_performance.modes.unfocused]
fps_cap = 12
pause_physics = false
pause_input = false

[runtime_performance.modes.minimized]
fps_cap = 0
pause_physics = true
pause_input = true

[runtime_performance.auto]
enabled = true                      # master switch for all automatic behavior

[runtime_performance.auto.idle]
enabled = true
unfocused_after_seconds = 60
unfocused_priority = 650
unfocused_target_mode = "unfocused"
minimized_after_seconds = 600
minimized_priority = 980
minimized_target_mode = "minimized"

[runtime_performance.auto.system.minimized]
enabled = true
priority = 1000
target_mode = "minimized"

[runtime_performance.auto.system.occluded]
enabled = true
priority = 1000
target_mode = "minimized"

[runtime_performance.auto.system.hidden]
enabled = true
priority = 1000
target_mode = "minimized"

[runtime_performance.auto.system.suspended]
enabled = true
priority = 1000
target_mode = "minimized"

[runtime_performance.auto.system.screen_locked]
enabled = true
priority = 1000
target_mode = "minimized"

[runtime_performance.auto.system.video_playback]
enabled = true
priority = 950
target_mode = "max"

[runtime_performance.auto.system.on_battery]
enabled = true
priority = 880
target_mode = "balanced"

[runtime_performance.auto.system.unfocused]
enabled = true
priority = 700
target_mode = "unfocused"

[runtime_performance.auto.rules.gameplay]
enabled = true
priority = 940
target_mode = "max"
```

Notes:

- `runtime_performance.active_mode` is legacy and no longer used.
- Defaults are populated with `ensure-defaults`; missing values are filled additively.

## Resolution Algorithm

Implementation: `assets/lua/runtime-performance.fnl`.

1. Read and normalize `control_mode` and `manual_mode`.
2. If `control_mode == manual`, return `effective_mode = manual_mode`.
3. If `control_mode == auto`:
   - If `auto.enabled == true`:
     - Collect active system rules (window/app/power/video state).
     - Collect active idle rules.
     - Collect active leases (gameplay and other callers).
   - If `auto.enabled == false`: skip all automatic candidates.
   - Pick highest priority; break ties by lease insertion order.
4. If no winner:
   - `restore_manual_on_clear = true`: use `manual_mode`.
   - otherwise: keep previous effective mode.
5. Resolve final policy from effective mode:
   - `fps_cap`
   - `pause_physics`
   - `pause_input`

## What Gets Applied

Application path: `RuntimePerformance.apply-settings(settings, state, engine)`.

Effects:

- `engine.set-target-fps(fps_cap)`
- `engine.set-physics-paused(pause_physics)`
- `engine.set-input-paused(pause_input)`
- If transitioning from `fps_cap=0` to `>0`, call `engine.request-frame()` to wake render loop.

State is cached as `state.last` and also mirrored in `app.*` fields for diagnostics/logging.

## Runtime Inputs (Auto Signals)

Signals are exposed in `assets/lua/engine-events.fnl` and handled in `assets/lua/main.fnl`.

Auto state fields currently driven:

- `focused`
- `minimized`
- `occluded`
- `hidden`
- `suspended`
- `screen_locked`
- `on_battery`
- `video_playback`

### X11/Xfce Visibility Policy

On some X11 window managers (including Xfce), `WINDOW_SHOWN`/`WINDOW_EXPOSED`
can fire while the app is still effectively out of view (for example during
workspace switches). To prevent `minimized -> unfocused` flapping:

- minimized-class state (`minimized`, `occluded`, `hidden`, `suspended`,
  `screen_locked`) is latched while unfocused.
- noisy clear events do not immediately clear minimized-class behavior.
- latch is cleared when focus is regained.

This policy is intentional and favors cooperative background behavior over
attempting to infer exact workspace visibility on X11.

Engine emits:

- `window-focus-changed`
- `window-minimized-changed`
- `window-occluded-changed`
- `window-hidden-changed`
- `app-suspended-changed`
- `screen-locked-changed`
- `on-battery-changed`
- `video-playback-active-changed`

## Reusable Gameplay Rule (for games)

To avoid per-game settings, gameplay boosting uses a shared rule plus leases.

Public app APIs:

- `app.activate-runtime-performance-gameplay-lease(id)`
- `app.clear-runtime-performance-gameplay-lease(id)`

Behavior:

- Uses shared settings under `runtime_performance.auto.rules.gameplay`.
- Creates/removes standard runtime leases (`source = "rule:gameplay"`).
- Any game can opt in by calling these APIs with a unique id.

Tetris integration:

- Activates gameplay lease while running.
- Clears lease on pause/stop/game over/drop.

## Idle Rules

Idle means no input events. Input activity is tracked from engine input signals:

- key up/down
- mouse move/button/wheel
- text input/edit
- gamepad axis/button

When enabled, idle contributes automatic rule candidates:

- after `unfocused_after_seconds`: `idle:unfocused`
- after `minimized_after_seconds`: `idle:minimized` (only while unfocused)

Idle rules are suppressed while interesting activity is present:

- active video playback
- active gameplay lease (`source = \"rule:gameplay\"`)

On next input event, idle stage is reset to active and mode restoration is immediate.

## Engine-side Implementation

`src/engine.cpp` binds and applies runtime controls:

- `set-target-fps(int)` / `get-target-fps()`
- `set-physics-paused(bool)` / `get-physics-paused()`
- `request-frame()`
- `is-on-battery()`
- `has-active-video-playback()`
- `set-screen-locked(bool)` (manual injection path)

Main loop behavior:

- `target_fps <= 0`: event-driven wait loop (`SDL_WaitEventTimeout`) and no frame delay cadence.
- physics step is skipped when `physics_paused_ == true`.
- audio/video/job/browser/lua work still runs according to loop conditions.

## Logging and Observability

`apply-runtime-performance-settings` logs only when a transition occurs, including:

- control mode
- effective mode
- fps cap
- physics paused
- source
- override id
- previous values

This avoids per-frame log spam while preserving mode transition auditability.

## Usage Examples

Switch to manual max:

```fennel
(app.set-runtime-performance-control-mode "manual")
(app.set-runtime-performance-manual-mode "max")
```

Switch to auto with balanced baseline:

```fennel
(app.set-runtime-performance-manual-mode "balanced")
(app.set-runtime-performance-control-mode "auto")
```

Use gameplay boost for a custom game:

```fennel
(app.activate-runtime-performance-gameplay-lease "my-game:session-42")
;; ... game runs ...
(app.clear-runtime-performance-gameplay-lease "my-game:session-42")
```

## Design Considerations and Trade-offs

- `manual` fully ignores auto rules by design (user intent is explicit).
- In `auto`, baseline falls back to `manual_mode` instead of introducing a separate `auto_baseline_mode`.
- Rule edits are currently treated as non-live (except `control_mode` / `manual_mode`, which users commonly change live).
- `minimized` default uses `fps_cap=0` and `pause_physics=true` for maximum background cooperation.
- `pause_physics` is mode-configurable to allow niche workloads.
- While unfocused on X11/Xfce, minimized-class behavior is intentionally sticky
  until focus returns, to avoid false visibility clears.
- Idle downgrade is based strictly on no input events; background compute is not considered activity.
- Idle never forces `minimized` while focused, so input wake remains immediate.

## Known Constraints

- If `minimized.fps_cap=0` and `minimized.pause_physics=false`, physics only advances when loop wakes on events/timeouts (not a steady simulation cadence).
- Gameplay leases snapshot rule settings at activation time; changing gameplay rule settings while a lease is already active does not retroactively mutate that lease.

## Tests

Primary tests:

- `assets/lua/tests/test-runtime-performance.fnl`
  - control-mode semantics
  - system rule priority/restore behavior
  - battery/video/gameplay lease behavior
  - fps and physics pause application
- `assets/lua/tests/test-tetris-view.fnl`
  - gameplay lease lifecycle integration

Suggested commands:

```bash
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-runtime-performance:main
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-tetris-view:main
```

## File Map

- Resolver and policy defaults: `assets/lua/runtime-performance.fnl`
- App integration and logging: `assets/lua/main.fnl`
- Engine events surface: `assets/lua/engine-events.fnl`
- Engine runtime controls/events: `src/engine.cpp`, `src/engine.h`
- Video playback activity query: `src/video_player.cpp`, `src/video_player.h`
- Gameplay consumer example: `assets/lua/tetris-view.fnl`
