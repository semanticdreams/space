# Selection Strategy

## 2D projection box vs. 3D frustum

- **Current path (2D projection box)**: project a selectable’s position to screen space (`glm.project`) and check against the drag rectangle. This is simple and fast, and works well for point-like items and HUD elements (where layout positions are already in screen space).
- **Limitation**: true 3D volumes don’t project to axis-aligned rectangles. Using only the projected center can miss partially visible objects or include those whose center is outside but corners intersect the box.

## Alternatives

- **Project corners to 2D**: project the 3D AABB corners, build the convex hull, and test against the selection rectangle. More accurate than center-only, but adds polygon-rect overlap logic per selectable.
- **3D frustum plane test (preferred for 3D)**: unproject the drag box corners to build a selection frustum, then test each selectable’s AABB against the frustum planes. This stays in 3D, handles perspective skew, and cleanly captures partial overlaps.

## Recommended hybrid

- For scene 3D selectables with extent: use the frustum-plane test.
- For HUD or point-like selectables: keep the 2D projection check for simplicity.
