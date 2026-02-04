# Resize & Layout Stability Report

This document chronicles the "Resize Jump" set of bugs, their root causes, and the applied fixes. It also lists potential residual issues for future reference.

## Resolved Issues

### 1. State Desync (FloatLayer vs Legacy Layout Targets)
*   **Symptoms:** Resizing handles would sometimes not appear, or they would control a "ghost" location that didn't match the visual element.
*   **Cause:** The `float-layer.fnl` implementation treated `movable-target` and `resize-target` as separate concerns. When the layout changed, one might update while the other lag behind.
*   **Fix:** Unified these targets into a single source of truth and updated the layouter to sync them atomically.

### 2. Stale Local Offset (Coordinate Space Instability)
*   **Symptoms:** Elements would "drift" or jump unexpectedly during resizing, especially when nested deep in the hierarchy or when the parent itself was moving.
*   **Cause:** The system calculated positions using local offsets relative to a parent. If the parent was resized or moved in the same frame, the calculated local offset became invalid effectively immediately, leading to incorrect world positioning in the next frame.
*   **Fix:** Modified `float-layer.fnl` to store and read `metadata.world-position` directly. This bypasses the vulnerable local-to-global calculation during active manipulation, using the absolute screen position as the source of truth.

### 3. Stale Resizable Entry (The "Ghost" Handle)
*   **Symptoms:** After dragging a tile to become a floating window, interaction with the resize handles would sometimes snap the element back to its tile state or position.
*   **Cause:** When `promote-tile-element` moved the element logic-wise from `Tiles` to `FloatLayer`, the Input system's registry (`app.resizables`) was not immediately informed. It held a "stale" reference to the element's *old* identity (targeting the raw `Layout` object).
*   **Fix:** Added mandatory `refresh-panel-resizables` calls in `hud.fnl` immediately after any promotion event to force the input registry to rebuild and find the new `FloatLayer` wrapper.

### 4. Resize Jump / Double Promotion (The "Reset" Bug)
*   **Symptoms:** Dragging an element (promoting it), then attempting to resize it would cause it to instantly jump back to its initial grid coordinates (e.g., 0,0 relative to the group).
*   **Cause:** A race condition often triggered by Bug #3. The stale input entry would trigger `promote-tile-element` on an element that was *already* floating. The original function assumed any call meant "initilize from scratch," so it overwrote the existing metadata (position, size) with default or nil values, effectively resetting the window.
*   **Fix:** 
    *   Modified `promote-tile-element` in `hud.fnl` to first check if the element is already a member of `self.float`.
    *   If found, it returns the *existing* metadata (preserving user-set position/size).
    *   It now also explicitly calls `tiles:detach-child` before attaching to float, preventing any ambiguity about ownership.

### 5. Drag Cancellation on Refresh (The "Snap to Left" Bug)
*   **Symptoms:** Resizing a "Ghost" element (one in Float but with Stale Tiles handle) would cause the window to "snap back" or stop resizing immediately.
*   **Cause:** `promote-tile-element` called `refresh-panel-resizables` even when finding an existing float element. This verified the registry but triggered `unregister` for the active drag entry, causing the Input System to immediately cancel the active drag operation.
*   **Fix strategy (Cross-Registry Refresh):** 
    We implemented a specialized refresh strategy in `hud.fnl`. When a promotion occurs:
    1.  The **Active** registry (e.g., `Resizables` if you are resizing) is **NOT** refreshed to avoid killing the drag. The current entry's target is updated JIT.
    2.  The **Passive** registry (e.g., `Movables`) **IS** refreshed immediately. This ensures that if the user subsequently tries to Drag the window, the `Movables` system has the correct (Float) target and doesn't try to move the stale (Tile) layout.
    
    This fixes both the "First Action Ignored" bug (by keeping active entry alive) AND the "Secondary Action Snaps Back" bug (by updating passive entries).

---

## Architecture Note: Failed Refactor Attempt

I attempted a **"Unified Entity"** refactor to completely eliminate the split identity (Wrappers vs Layouts) problem. The goal was to use a dynamic Proxy object that handled drag/resize by querying the element's current state (Tiles vs Float) at runtime, removing the need for "Promotion" patching.

**Why it failed:**
*   **Coordinate Space Mismatch:** The `Tiles` container and `FloatLayer` container generally operate in different coordinate spaces (Layout-Relative vs World-Absolute).
*   **The Blocker:** Validating the Refactor revealed that the Proxy could not reliably calculate the initial drag offset because `element.layout.position` (in Tiles) does not map 1:1 to World Position without a verified `local-to-world` transform service, which implies extensive changes to `LayoutRoot`.
*   **Resolution:** I have reverted to the **Stable Patch** (Fix #5 above) which has been verified to work across all test cases.
