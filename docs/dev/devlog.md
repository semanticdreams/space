# Devlog

## 2026-07-31
Runtime portability tightened with asset discovery that resolves from the executable through a deduplicated search order while preserving explicit overrides, and native logging now settles in a deliberate user log directory after dotenv has a chance to provide `SPACE_LOG_DIR`, keeping CLI, REPL, module, developer, installed, and portable runs predictable instead of scattering assets or `gl.log` around arbitrary launch directories.

## 2026-07-30
Late July added grounded camera controls and physics anchor dragging through a new sandbox interaction toolbar, migrated the presentation layer from app-global assumptions to activity-owned delegates, shipped external-unit MCP tooling for loader-neutral user code, and matured the daily devlog automation with a retrospective journal backfill — giving the project a durable narrative record as it builds toward the next graph and world-editing milestones.

## 2026-07-14
By mid-July, the project consolidated its operating loop around panel transfer, the repository workbench, conversation-first supervision, and the new VitePress knowledge base, turning months of scattered architecture notes into a navigable map for future graph, world-building, and live-development milestones.

## 2026-06-15
June pushed Space toward portability and broader authoring workflows, pairing Windows cross-compilation and packaging smoke-test work with board canvas mode, semantic connectors, item selection, and hot-reload cache cleanup so the workspace could travel beyond the original Linux development loop.

## 2026-05-08
May shifted the project toward live agent-assisted development: the agent runner, presets, MCP transport, OpenCode streaming, reloadable units, user-code scanning, and Lua-owned HTTP pieces started turning Space into an environment that can inspect and reshape itself while it runs.

## 2026-04-16
April was a stabilization pass for the growing world-building system, tightening lifecycle ownership, signal cleanup, composable state handling, stylus drawing, Yojimbo experiments, and canvas modes so interactive surfaces could grow without silent callbacks or tangled mode logic.

## 2026-03-18
March turned the newly merged Lua/Fennel stack into a world-building platform: terrain heightfields, graph editing, exposed world entities, lighting, and containment work converged so scenes were no longer just rendered surfaces but editable environments connected through the graph.

## 2026-02-16
Restructured docs: combined public docs with dev docs in a new VitePress project, deployed via GitHub Pages to spaceui.org.
A recent attempt at creating a new instanced quad based rectangle and text rendering system stalled, see code in next-app. Live development is needed to understand the system and harmonize layout and rendering designs.

## 2026-02-09
Added Xapian bindings for in-app search. Fixed input text alignment for inputs with extra space. Main challenge is how to structure the graph system to support specific features such as agentic coding, live state exploration, visual programming, knowledge management, etc. while remaining generic and convenient. A possible next step is to add notebooks with notebook pages (or nested notebooks) inspired by gtoolkit in order to provide a structure for the implementation of new features and to keep track of the alignment of development efforts with project goals.

## 2026-02-08
Status: Most features from the Python prototype have been recreated in the new Fennel/C++ implementation over the last few months.

## 2025-10-01
By October, Space's Python prototype had become a staging ground for a deeper Lua/Fennel migration: the long-lived branch carried the engine toward a scriptable UI and graph-centered runtime, keeping the momentum from the September Fennel rendering experiments while avoiding noisy mainline churn until the new architecture could land as a coherent replacement.

## 2025-09-24
Changed to load classes in Python prototype directly from z folder rather than through DB-based entities
to avoid a strange system-dependent problem.
As a result, editing class entities from within the prototype world will no longer work.
Prototype is reaching its end of life so this is ok.

Fixed fbo update issue by updating Lua's fbo handle on viewport change.

## 2025-09-17
Fennel implementation has basic triangle renderering and initial UI code (rectangles, layout, widget).
Output is rendered to a framebuffer displayed on a texture within the scene created by the prototype.
Entities will be file-based.

## 2025-09-16
In the process of replacing Python prototype with C++/Fennel implementation.
Prototype has skybox, line, triangle, text (msdf), image, point, mesh and sub-world **renderers**.
**UI layout system** has measure pass and layout pass. Layout nodes have to be assembled manually,
no uniform widget system. Since there is no widget hierarchy, every object stores
references to anything it creates, to be able to drop it when it's dropped.
**Entities** (base units of knowledge management in space), stored in sqlite, subclasses of `Entity`.
Each entity class defines view, preview, color, load & dump methods plus custom behavior. Entity
superclass tracks type, id, color and changed signal, has base get, create, save, delete methods.
Class entities are used for most of the prototype code. Jump to internal entities was problematic 
due to lacking internal development tools. Currently, 2-way sync between file system based classes
and class entities enables working from both external and internal environments.
**Space graph**, called dynamic graph in the prototype, implemented in classes `DynamicGraph`
and `DynamicGraphChild`. Nodes positioned using force layout, multiple LOD levels and full view added to HUD on selection.
Root graph entity (ID 18) is mounted into dynamic graph.

![Space Prototype Screenshot](./space-prototype-screenshot1.png)
