# Devlog

## 2026-02-16
Restructured docs: combined public docs with dev docs in a new VitePress project, deployed via GitHub Pages to spaceui.org.
A recent attempt at creating a new instanced quad based rectangle and text rendering system stalled, see code in next-app. Live development is needed to understand the system and harmonize layout and rendering designs.

## 2026-02-09
Added Xapian bindings for in-app search. Fixed input text alignment for inputs with extra space. Main challenge is how to structure the graph system to support specific features such as agentic coding, live state exploration, visual programming, knowledge management, etc. while remaining generic and convenient. A possible next step is to add notebooks with notebook pages (or nested notebooks) inspired by gtoolkit in order to provide a structure for the implementation of new features and to keep track of the alignment of development efforts with project goals.

## 2026-02-08
Status: Most features from the Python prototype have been recreated in the new Fennel/C++ implementation over the last few months.

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

