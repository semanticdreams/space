Binding preload plan
====================

Goals
- Move all engine bindings to `package.preload` and require them explicitly from Lua/Fennel.
- Keep module names direct (no root namespace), and use wrapper suffixes only when needed.
- Use module factory functions instead of `.new` constructors while keeping usertypes for methods.

Plan
1) Convert C++ bindings to `package.preload` modules.
   - Status: done for `appdirs`, `audio`, `callbacks`, `colors`, `fs`, `gl`, `glm`, `http`, `json`, `jobs`,
     `keyring`, `notify`, `ray-box`, `shaders`, `textures`, `terminal`, `input-state`, `tray`,
     `tree-sitter`, `vector-buffer`, `webbrowser`, `bt`, and `force-layout`.

2) Update Fennel/Lua to `require` bindings explicitly.
   - Status: done; keep new modules aligned by adding `(local x (require :x))` at the top.
   - Coverage:
     - `appdirs`: done
     - `audio`: done
     - `bt`: done
     - `colors`: done
     - `fs`: done
     - `gl`: done
     - `glm`: done
     - `http`: done
     - `input-state`: done
     - `json`: done
     - `keyring`: done
     - `notify`: done
     - `ray-box`: done
     - `shaders`: done
     - `terminal`: done
     - `textures`: done
     - `tray`: done
     - `tree-sitter`: done
     - `vector-buffer`: done
     - `webbrowser`: done
     - `jobs`: done
     - `callbacks`: done
     - `force-layout`: done

3) Keep wrapper naming consistent with roles.
   - Status: done (`terminal-widget`, `input-state-router`, `tray-manager`, `notify-manager`).

4) Replace `.new` constructors with factories.
   - Status: done for `terminal.Terminal(...)`, `VectorBuffer(...)`, `ForceLayout(...)`, `bt.*(...)`.

5) Update docs/tests to match module names and factory usage.
   - Status: done; update docs when new bindings or factories change.
