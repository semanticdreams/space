# Experimental Fennel Constraints Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a blocking experimental Fennel constraint gate that combines tree-sitter source facts with executable scenario checks before normal Fennel tests run.

**Architecture:** Extend the existing tree-sitter Lua binding to parse Fennel, then build a Fennel-only constraints subsystem under `assets/lua/constraints/`. The runner resolves repo and external targets, extracts static facts, runs independent static and scenario rules, applies reviewed baselines/allowlists, emits structured diagnostics, and exits nonzero for every non-pass status. `make constraints` and a CTest fixture make the gate blocking before Fennel tests.

**Tech Stack:** C++17/sol2 tree-sitter binding, vendored `external/tree-sitter/fennel`, Fennel modules under `assets/lua`, existing `fs`/`json` Lua bindings, existing `build/space -m module:main` runtime, Make, CMake/CTest.

## Global Constraints

- This is explicitly an experiment.
- Constraints should be enforced from the start so the team learns whether they are useful under real pressure.
- If a constraint is noisy or wrong, the remedy is to fix it or remove it through reviewed code, not to bypass the gate.
- The default target is the repository Fennel code under `assets/lua/`.
- Production modules do not import or call constraint modules.
- The MVP should expose traversal helpers and fact tables only.
- The MVP does not need a general query language, complete semantic analysis, macro-expanded analysis, or broad lint coverage.
- Supported target kinds are `:repo`, `:unit`, `:app`, and `:files`.
- Diagnostics should always identify the target as well as the file and constraint id.
- Every status other than `pass` exits nonzero.
- Add a `make constraints` target using `SPACE_DISABLE_AUDIO=1`, absolute `SPACE_ASSETS_PATH`, and configured `FENNEL_PATH` / `FENNEL_MACRO_PATH`.
- Add a CTest target for experimental constraints and make normal Fennel tests depend on it.
- The target name and docs should keep the word `experimental`, but the target must be blocking.
- Structure and formatting constraints must be blocking immediately without requiring a large cleanup branch first.
- Existing violations may be represented in an explicit reviewed baseline or allowlist.
- The baseline is not a bypass flag; it is versioned project data that records known exceptions with file, rule, current measure, and reason.
- The gate blocks when a new violation appears.
- The gate blocks when an existing baseline violation worsens.
- The gate blocks when a baseline entry no longer matches the current code.
- The gate blocks when a required constraint disappears.
- The gate blocks when a constraint fails or is interrupted.
- Do not replace human review.
- Do not replace unit/integration tests.
- Do not require production modules to annotate themselves or import constraint modules.
- Do not build a full static type system or macro-expanded semantic analyzer in the MVP.
- Do not make constraints advisory-only; if they are bad, fix or remove them.
- Use TDD for every task: write failing tests first, run them, implement, run focused validation, then commit.
- Use commit message format `type(scope): summary`.

---

## File Structure

- `src/lua_tree_sitter.cpp`: expose Fennel parsing and source point locations through the existing tree-sitter Lua module.
- `assets/lua/constraints/diagnostics.fnl`: normalize diagnostics and build aggregate result summaries.
- `assets/lua/constraints/runner.fnl`: parse runner arguments, run independent constraints, apply baseline policy, print JSON, and exit with blocking status.
- `assets/lua/constraints/targets.fnl`: resolve repo, unit, app, and explicit-file targets.
- `assets/lua/constraints/source.fnl`: discover/read/parse Fennel source files and expose AST traversal helpers.
- `assets/lua/constraints/facts.fnl`: convert parsed files into stable source facts and structure metrics.
- `assets/lua/constraints/baseline.fnl`: apply reviewed baseline/allowlist entries.
- `assets/lua/constraints/baseline-data.fnl`: versioned required rule ids and accepted existing structure findings.
- `assets/lua/constraints/scenarios.fnl`: run executable scenario constraints with the normal test app runtime.
- `assets/lua/constraints/rules/init.fnl`: deterministic rule registry.
- `assets/lua/constraints/rules/scene-sandbox.fnl`: Scene/Sandbox architectural constraints.
- `assets/lua/constraints/rules/lifecycle.fnl`: lifecycle and required-runtime constraints.
- `assets/lua/constraints/rules/test-isolation.fnl`: test-global restoration constraints.
- `assets/lua/constraints/rules/layout.fnl`: layout/rendering constraints.
- `assets/lua/constraints/rules/structure.fnl`: structure and style constraints.
- `assets/lua/tests/test-tree-sitter-fennel.fnl`: binding tests.
- `assets/lua/tests/test-constraints-*.fnl`: focused tests for runner, targets, facts, baseline, and rules.
- `Makefile` and `CMakeLists.txt`: blocking validation integration.
- `docs/dev/experimental-constraints.md` and `AGENTS.md`: developer workflow documentation.

---

### Task 1: Fennel tree-sitter binding

**Files:**
- Modify: `src/lua_tree_sitter.cpp`
- Create: `assets/lua/tests/test-tree-sitter-fennel.fnl`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes: existing `tree-sitter` preload module and vendored `tree_sitter_fennel()` grammar.
- Produces:
  ```fennel
  (local ts (require :tree-sitter))
  (ts.parse source) ; -> TSTree, defaults to C++ for compatibility
  (ts.parse source {:language :fennel}) ; -> TSTree
  (tree:root) ; -> TSNode
  (node:type) ; -> string
  (node:child-count) ; -> integer
  (node:child index) ; -> TSNode
  (node:start-byte) ; -> integer
  (node:end-byte) ; -> integer
  (node:start-point) ; -> {:row integer :column integer}
  (node:end-point) ; -> {:row integer :column integer}
  (node:is-null) ; -> boolean
  (node:sexpr) ; -> string
  ```

- [ ] **Step 1: Write the failing binding test**

Create `assets/lua/tests/test-tree-sitter-fennel.fnl`:

```fennel
(local tests [])
(local ts (require :tree-sitter))

(fn fennel-parser-produces-root-and-locations []
  (local source "(fn hello [name]\n  (print name))\n")
  (local tree (ts.parse source {:language :fennel}))
  (local root (tree:root))
  (assert (not (root:is-null)))
  (assert (> (root:child-count) 0))
  (assert (string.find (root:sexpr) "fn" 1 true))
  (local start (root:start-point))
  (local finish (root:end-point))
  (assert (= start.row 0))
  (assert (= start.column 0))
  (assert (>= finish.row 1))
  (assert (>= (root:end-byte) (root:start-byte))))

(fn default-cpp-parser-still-works []
  (local tree (ts.parse "int main() { return 0; }"))
  (local root (tree:root))
  (assert (not (root:is-null)))
  (assert (= (root:type) "translation_unit")))

(fn unknown-language-fails-loudly []
  (local (ok err) (pcall (fn []
                           (ts.parse "(print :x)" {:language :unknown}))))
  (assert (not ok))
  (assert (string.find (tostring err) "tree-sitter.parse unsupported language" 1 true)))

(table.insert tests {:name "tree-sitter parses Fennel with locations"
                     :fn fennel-parser-produces-root-and-locations})
(table.insert tests {:name "tree-sitter default C++ parser remains compatible"
                     :fn default-cpp-parser-still-works})
(table.insert tests {:name "tree-sitter rejects unknown languages"
                     :fn unknown-language-fails-loudly})

{:name "tree-sitter-fennel"
 :tests tests}
```

Add `:tests.test-tree-sitter-fennel` to `assets/lua/tests/fast.fnl`.

- [ ] **Step 2: Run the focused test and confirm it fails**

Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-tree-sitter-fennel:main
```

Expected: FAIL because `ts.parse` does not accept `{:language :fennel}` and `TSNode` does not expose point locations.

- [ ] **Step 3: Implement language selection and source points**

In `src/lua_tree_sitter.cpp`:
- declare `extern "C" const TSLanguage *tree_sitter_fennel();`;
- keep `ts.parse(source)` using C++ to preserve compatibility;
- accept optional `sol::table opts`;
- read `opts["language"]` as a string-compatible Lua value;
- support `"cpp"`, `":cpp"`, `"fennel"`, and `":fennel"`;
- throw `sol::error("tree-sitter.parse unsupported language: " + language)` for any other value;
- expose `start-point` and `end-point` methods returning Lua tables with `row` and `column`.

- [ ] **Step 4: Build and rerun the focused test**

Run:

```bash
make build
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-tree-sitter-fennel:main
```

Expected: PASS.

- [ ] **Step 5: Commit the parser binding**

```bash
git add src/lua_tree_sitter.cpp assets/lua/tests/test-tree-sitter-fennel.fnl assets/lua/tests/fast.fnl
git commit -m "feat(lua): expose fennel tree-sitter parsing"
```

---

### Task 2: Diagnostics and runner core

**Files:**
- Create: `assets/lua/constraints/diagnostics.fnl`
- Create: `assets/lua/constraints/runner.fnl`
- Create: `assets/lua/tests/test-constraints-runner.fnl`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes: Fennel runtime module entry point convention `constraints.runner:main`.
- Produces:
  ```fennel
  (Diagnostics.violation opts) ; -> normalized diagnostic
  (Diagnostics.framework-failure opts) ; -> normalized diagnostic
  (Diagnostics.summary status diagnostics) ; -> result table

  {:constraint-id string
   :family string
   :severity :error|:warning
   :message string
   :target {:kind :repo|:unit|:app|:files :name string}
   :file string|nil
   :line integer|nil
   :column integer|nil
   :evidence table
   :hint string}

  (Runner.run opts) ; -> {:status :pass|:violations|:fail|:interrupted
                    ;     :counts {:total integer :by-family table :by-severity table}
                    ;     :diagnostics []}
  (Runner.main argv) ; prints one JSON summary and exits 0 only for :pass
  ```

- [ ] **Step 1: Write failing runner tests**

Create `assets/lua/tests/test-constraints-runner.fnl` with tests that verify:
- a no-op rule returns `:pass`;
- a rule returning one diagnostic returns `:violations`;
- a crashing rule returns `:fail`;
- normalized diagnostics require `constraint-id`, `family`, `severity`, `message`, and `hint`;
- `Runner.main` prints a JSON-compatible summary through an injectable `:print` function and uses injectable `:exit` to report exit code.

- [ ] **Step 2: Run the focused test and confirm it fails**

Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-constraints-runner:main
```

Expected: FAIL because `constraints.runner` and `constraints.diagnostics` do not exist.

- [ ] **Step 3: Implement diagnostic normalization**

In `assets/lua/constraints/diagnostics.fnl`, implement:
- required field assertions with explicit messages such as `constraint diagnostic missing constraint-id`;
- default `:severity :error`;
- default `:evidence {}`;
- source locations using one-based `:line` and `:column` when supplied;
- `summary` counts by family and severity.

- [ ] **Step 4: Implement runner aggregation**

In `assets/lua/constraints/runner.fnl`, implement:
- `run-rule` using `xpcall` and `debug.traceback`;
- status precedence `:interrupted` > `:fail` > `:violations` > `:pass`;
- `run` accepting `{:rules [] :target target :timeout-seconds integer|nil}`;
- `main` accepting injected `:argv`, `:print`, and `:exit` for tests;
- JSON summary output using `(require :json).dumps`.

- [ ] **Step 5: Register test module and validate**

Add `:tests.test-constraints-runner` to `assets/lua/tests/fast.fnl`, then rerun the command from Step 2.

Expected: PASS.

- [ ] **Step 6: Commit runner core**

```bash
git add assets/lua/constraints/diagnostics.fnl assets/lua/constraints/runner.fnl assets/lua/tests/test-constraints-runner.fnl assets/lua/tests/fast.fnl
git commit -m "feat(lua): add experimental constraint runner core"
```

---

### Task 3: Target resolution and source discovery

**Files:**
- Create: `assets/lua/constraints/targets.fnl`
- Create: `assets/lua/constraints/source.fnl`
- Create: `assets/lua/tests/test-constraints-source.fnl`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes: `tree-sitter.parse(source, {:language :fennel})`, `fs.stat`, `fs.list-dir`, `fs.read-file`, and path helpers available in the repo.
- Produces:
  ```fennel
  (Targets.resolve argv env) ; -> target config

  {:kind :repo|:unit|:app|:files
   :name string
   :roots [absolute-path-string ...]
   :files [absolute-path-string ...]
   :module-roots [absolute-path-string ...]
   :suites [:scene-sandbox :lifecycle :layout :structure]}

  (Source.discover target) ; -> [file-record ...]

  {:target target
   :path absolute-path-string
   :module string
   :source string
   :tree TSTree
   :root TSNode}

  (Source.node-text source node) ; -> string
  (Source.node-location node) ; -> {:line integer :column integer}
  (Source.walk node f) ; calls f for every node depth-first
  ```

- [ ] **Step 1: Write failing target/source tests**

Create `assets/lua/tests/test-constraints-source.fnl` with tests for:
- `Targets.resolve [] {}` returns `:repo`, root `<repo>/assets/lua`, and suites including all four families;
- `Targets.resolve ["--target" "unit" "--root" "/tmp/space/constraints-unit"] {}` returns `:unit`;
- `Targets.resolve ["--target" "app" "--root" "/tmp/space/constraints-app"] {}` returns `:app`;
- `Targets.resolve ["--target" "files" "--file" "/tmp/space/constraints-one.fnl"] {}` returns `:files`;
- `Source.discover` recursively includes `.fnl` files and excludes non-Fennel files;
- explicit files outside `assets/lua/` parse successfully and retain target identity.

- [ ] **Step 2: Run the focused test and confirm it fails**

Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-constraints-source:main
```

Expected: FAIL because `constraints.targets` and `constraints.source` do not exist.

- [ ] **Step 3: Implement CLI target resolution**

In `assets/lua/constraints/targets.fnl`, implement exact flags:
- default: `--target repo`;
- `--target repo`;
- `--target unit --root PATH`;
- `--target app --root PATH`;
- `--target files --file PATH` with repeated `--file`;
- repeated `--root` for `repo`, `unit`, and `app`;
- fail loudly for missing values and unsupported target names.

- [ ] **Step 4: Implement source discovery and parsing**

In `assets/lua/constraints/source.fnl`:
- recurse roots using available filesystem helpers;
- include only paths matching `%.fnl$`;
- sort paths lexicographically for deterministic diagnostics;
- compute module names relative to the first matching module root by removing `.fnl` and replacing `/` with `.`;
- parse every file with `tree-sitter.parse source {:language :fennel}`;
- expose `node-text`, `node-location`, and `walk`.

- [ ] **Step 5: Register test module and validate**

Add `:tests.test-constraints-source` to `assets/lua/tests/fast.fnl`, then rerun the command from Step 2.

Expected: PASS.

- [ ] **Step 6: Commit target/source support**

```bash
git add assets/lua/constraints/targets.fnl assets/lua/constraints/source.fnl assets/lua/tests/test-constraints-source.fnl assets/lua/tests/fast.fnl
git commit -m "feat(lua): add constraint targets and source discovery"
```

---

### Task 4: Static Fennel fact extraction

**Files:**
- Create: `assets/lua/constraints/facts.fnl`
- Create: `assets/lua/tests/test-constraints-facts.fnl`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes:
  ```fennel
  (Source.discover target) ; -> file records
  (Source.node-text source node) ; -> string
  (Source.node-location node) ; -> {:line integer :column integer}
  ```
- Produces:
  ```fennel
  (Facts.extract file-records) ; -> fact-db

  {:files [file-facts ...]
   :by-file {path file-facts}}

  {:target target
   :path string
   :module string
   :requires [{:module string :line integer :column integer :form string}]
   :definitions [{:kind :fn|:local|:global :name string :top-level? boolean :line integer :column integer :length integer :form string}]
   :exports [{:key string :line integer :column integer :form string}]
   :calls [{:callee string :receiver string|nil :method string|nil :line integer :column integer :form string :enclosing-fn string|nil}]
   :accesses [{:path [string ...] :text string :line integer :column integer :form string}]
   :mutations [{:op :set|:tset|:global :path [string ...] :line integer :column integer :form string :enclosing-fn string|nil}]
   :metrics {:module-lines integer
             :max-nesting-depth integer
             :max-anonymous-callback-depth integer
             :max-table-literal-size integer
             :functions [{:name string :line integer :column integer :length integer :max-nesting-depth integer}]}}
  ```

- [ ] **Step 1: Write failing fact extraction tests**

Create `assets/lua/tests/test-constraints-facts.fnl` using an explicit external temp file source:

```fennel
(local source "(local Scene (require :scene))\n(fn build [world]\n  (set world.state.scene.panels [])\n  (Scene.activate world)\n  {:render build})\n")
```

Assert facts include:
- require module `"scene"`;
- definition name `"build"`;
- export key `"render"`;
- call callee `"Scene.activate"`;
- access path `["world" "state" "scene" "panels"]`;
- mutation path `["world" "state" "scene" "panels"]`;
- positive module and function lengths.

Add a second source with nested anonymous functions and a table literal to assert metric extraction.

- [ ] **Step 2: Run the focused test and confirm it fails**

Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-constraints-facts:main
```

Expected: FAIL because `constraints.facts` does not exist.

- [ ] **Step 3: Implement form-oriented traversal helpers**

In `assets/lua/constraints/facts.fnl`, implement extraction by combining tree-sitter node traversal with source slices:
- identify top-level list forms by source text starting with `(fn `, `(local `, `(global `, `(set `, and `(tset `;
- identify table forms by source text starting with `{`;
- keep source locations from tree-sitter nodes;
- keep raw form snippets in every fact for rule evidence.

- [ ] **Step 4: Extract required facts and metrics**

Implement:
- require detection for `(require :module)` and `(require "module")`;
- definition detection for `(fn name ...)`, `(local name ...)`, and `(global name ...)`;
- returned table export keys from top-level table literals;
- call detection for symbol heads and method-style `receiver:method`;
- access/mutation paths by splitting dotted symbols such as `world.state.scene.panels`;
- module line count, approximate function length, maximum nesting depth, table literal size, and anonymous callback depth.

- [ ] **Step 5: Register test module and validate**

Add `:tests.test-constraints-facts` to `assets/lua/tests/fast.fnl`, then rerun the command from Step 2.

Expected: PASS.

- [ ] **Step 6: Commit fact extraction**

```bash
git add assets/lua/constraints/facts.fnl assets/lua/tests/test-constraints-facts.fnl assets/lua/tests/fast.fnl
git commit -m "feat(lua): extract static fennel constraint facts"
```

---

### Task 5: Baseline and allowlist policy

**Files:**
- Create: `assets/lua/constraints/baseline.fnl`
- Create: `assets/lua/constraints/baseline-data.fnl`
- Create: `assets/lua/tests/test-constraints-baseline.fnl`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes: diagnostics from `constraints.diagnostics`.
- Produces:
  ```fennel
  (Baseline.load) ; -> baseline-data

  {:required-rule-ids [string ...]
   :entries [baseline-entry ...]}

  {:constraint-id string
   :file string
   :line integer
   :fingerprint string
   :measure integer
   :reason string}

  (Baseline.fingerprint diagnostic) ; -> string
  (Baseline.apply diagnostics baseline-data present-rule-ids) ; -> {:diagnostics [] :baseline-diagnostics []}
  ```

- [ ] **Step 1: Write failing baseline tests**

Create tests proving:
- an exact matching baseline entry suppresses a matching diagnostic;
- a diagnostic with a larger `evidence.measure` than the baseline entry emits `baseline.worsened`;
- a baseline entry with no current matching diagnostic emits `baseline.stale`;
- a `required-rule-ids` entry missing from `present-rule-ids` emits `baseline.required-rule-missing`;
- baseline diagnostics use family `"baseline"` and severity `:error`.

- [ ] **Step 2: Run the focused test and confirm it fails**

Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-constraints-baseline:main
```

Expected: FAIL because baseline modules do not exist.

- [ ] **Step 3: Implement baseline data and policy**

Create `assets/lua/constraints/baseline-data.fnl` with all required MVP rule ids and an initially empty `:entries` vector. The required rule ids are:

```fennel
["scene.no-legacy-world-state-scene"
 "scene.activity-slot-ownership"
 "scene.sandbox-activation-contract"
 "scene.active-render-context-routing"
 "lifecycle.event-registration-cleanup"
 "lifecycle.global-mutation-restoration"
 "lifecycle.required-runtime-fails-loudly"
 "layout.no-setters-in-layouters"
 "layout.owned-child-drop"
 "layout.interactive-context-assertion"
 "structure.max-nesting-depth"
 "structure.max-function-length"
 "structure.max-module-length"
 "structure.large-inline-structure"
 "structure.style-doctrine"]
```

Implement `Baseline.apply` so only exact `constraint-id`, `file`, `line`, and `fingerprint` matches are eligible for suppression.

- [ ] **Step 4: Integrate baseline into runner**

Modify `constraints.runner.fnl` so `Runner.run`:
- collects present rule ids from `rule.id`;
- applies `Baseline.apply` after all rules run;
- includes baseline diagnostics in the aggregate result;
- exits nonzero when baseline diagnostics exist.

- [ ] **Step 5: Register test module and validate**

Add `:tests.test-constraints-baseline` to `assets/lua/tests/fast.fnl`, then rerun the command from Step 2 and run `tests.test-constraints-runner`.

Expected: PASS.

- [ ] **Step 6: Commit baseline policy**

```bash
git add assets/lua/constraints/baseline.fnl assets/lua/constraints/baseline-data.fnl assets/lua/constraints/runner.fnl assets/lua/tests/test-constraints-baseline.fnl assets/lua/tests/fast.fnl
git commit -m "feat(lua): add constraint baseline policy"
```

---

### Task 6: Scene/Sandbox constraint family

**Files:**
- Create: `assets/lua/constraints/scenarios.fnl`
- Create: `assets/lua/constraints/rules/scene-sandbox.fnl`
- Create: `assets/lua/tests/test-constraints-rules-scene-sandbox.fnl`
- Modify: `assets/lua/tests/runner.fnl`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes:
  ```fennel
  (Facts.extract file-records) ; -> fact-db
  (Diagnostics.violation opts) ; -> diagnostic
  ```
- Produces:
  ```fennel
  (Scenarios.with-test-app f) ; -> f result with real test app initialized and shut down

  (SceneSandbox.rules) ; -> [rule ...]

  {:id string
   :family string
   :targets [:repo ...]
   :kind :static|:scenario
   :run (fn [ctx] diagnostics)}

  {:target target :facts fact-db :files file-records}
  ```

- [ ] **Step 1: Write failing Scene/Sandbox rule tests**

Create tests with synthetic fact DBs and real scenario execution covering valid and invalid cases for:
- `scene.no-legacy-world-state-scene`: flags `world.state.scene.*` outside allowlisted migration files;
- `scene.activity-slot-ownership`: Graph, Drawing, and Board modules must call `ensure-activity-slot` and `activate-activity-slot` with their own ids, not `"sandbox"`;
- `scene.sandbox-activation-contract`: `sandbox-activity-unit.fnl` must require `runtime.scene`, activate `"sandbox"`, hide Canvas, prefer Scene interaction, install root actions, install target predicate, and install update hook;
- `scene.active-render-context-routing`: executable scenario verifies active Scene slot context supplies render vectors.

- [ ] **Step 2: Run the focused test and confirm it fails**

Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-constraints-rules-scene-sandbox:main
```

Expected: FAIL because `constraints.rules.scene-sandbox` and scenario helpers do not exist.

- [ ] **Step 3: Expose reusable test app setup**

Modify `assets/lua/tests/runner.fnl` to export:

```fennel
:setup-test-env setup-test-env
:shutdown-test-env (fn []
                     (when (and app app.drop)
                       (app.drop))
                     (set app {}))
```

Keep existing `run-tests` and `run-modules` behavior unchanged.

- [ ] **Step 4: Implement scenario helper**

In `constraints/scenarios.fnl`, implement `with-test-app` by requiring `tests.runner`, calling `setup-test-env`, running `f` with `xpcall`, always calling `shutdown-test-env`, and rethrowing failures.

- [ ] **Step 5: Implement Scene/Sandbox rules**

In `constraints/rules/scene-sandbox.fnl`, export the four required rules. Each diagnostic must include:
- family `"scene-sandbox"`;
- one of the required rule ids;
- file, line, column when static evidence exists;
- evidence containing the matched form or scenario assertion name;
- a repair hint explaining the expected Scene/Sandbox ownership.

- [ ] **Step 6: Register test module and validate**

Add `:tests.test-constraints-rules-scene-sandbox` to `assets/lua/tests/fast.fnl`, then rerun the command from Step 2.

Expected: PASS.

- [ ] **Step 7: Commit Scene/Sandbox constraints**

```bash
git add assets/lua/constraints/scenarios.fnl assets/lua/constraints/rules/scene-sandbox.fnl assets/lua/tests/test-constraints-rules-scene-sandbox.fnl assets/lua/tests/runner.fnl assets/lua/tests/fast.fnl
git commit -m "feat(lua): add scene sandbox constraints"
```

---

### Task 7: Lifecycle and test-isolation constraint families

**Files:**
- Create: `assets/lua/constraints/rules/lifecycle.fnl`
- Create: `assets/lua/constraints/rules/test-isolation.fnl`
- Create: `assets/lua/tests/test-constraints-rules-lifecycle.fnl`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes: fact DB shape from Task 4 and diagnostics from Task 2.
- Produces:
  ```fennel
  (Lifecycle.rules) ; -> rules for lifecycle family
  (TestIsolation.rules) ; -> lifecycle-family rules for test globals
  ```

- [ ] **Step 1: Write failing lifecycle tests**

Create tests for valid and invalid inputs:
- event/update registration with `:connect`, `register`, or `app.engine.events.updated:connect` must have cleanup evidence with `disconnect`, `unregister`, `clear`, or `drop` in the same file;
- tests mutating sensitive globals must restore them;
- required runtime dependencies must fail loudly using `assert` or `error`, not silent fallback forms.

Sensitive globals are exactly:

```fennel
["app.renderers"
 "app.lights"
 "app.engine"
 "app.activity-registry"
 "app.physics-containment-config"
 "package.loaded"]
```

- [ ] **Step 2: Run the focused test and confirm it fails**

Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-constraints-rules-lifecycle:main
```

Expected: FAIL because lifecycle rule modules do not exist.

- [ ] **Step 3: Implement lifecycle cleanup rule**

In `constraints/rules/lifecycle.fnl`, implement `lifecycle.event-registration-cleanup`:
- flag files with registration calls and no cleanup calls;
- treat functions named `drop`, `cleanup`, `teardown`, `shutdown`, and `unload` as cleanup paths;
- include evidence listing registration forms and missing cleanup forms.

- [ ] **Step 4: Implement required-runtime failure rule**

Implement `lifecycle.required-runtime-fails-loudly`:
- flag forms using `or`, `when`, or `if` to synthesize runtime state after missing required app/runtime fields;
- allow forms that contain `assert` or `error` in the same enclosing function;
- use hint `"Assert required runtime state instead of silently no-oping or synthesizing canonical state."`.

- [ ] **Step 5: Implement test global restoration rule**

In `constraints/rules/test-isolation.fnl`, implement `lifecycle.global-mutation-restoration`:
- apply to files whose path contains `/tests/`;
- flag sensitive global mutations not accompanied by snapshot and restore evidence in the same function;
- accept `with-restored-app-fields`, direct snapshot table restore, or `pcall` cleanup restore patterns.

- [ ] **Step 6: Register test module and validate**

Add `:tests.test-constraints-rules-lifecycle` to `assets/lua/tests/fast.fnl`, then rerun the command from Step 2.

Expected: PASS.

- [ ] **Step 7: Commit lifecycle constraints**

```bash
git add assets/lua/constraints/rules/lifecycle.fnl assets/lua/constraints/rules/test-isolation.fnl assets/lua/tests/test-constraints-rules-lifecycle.fnl assets/lua/tests/fast.fnl
git commit -m "feat(lua): add lifecycle constraints"
```

---

### Task 8: Layout and rendering constraint family

**Files:**
- Create: `assets/lua/constraints/rules/layout.fnl`
- Create: `assets/lua/tests/test-constraints-rules-layout.fnl`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes: fact DB shape from Task 4 and diagnostics from Task 2.
- Produces:
  ```fennel
  (LayoutRules.rules) ; -> layout/rendering family rules
  ```

- [ ] **Step 1: Write failing layout rule tests**

Create valid and invalid source fact tests for:
- `layout.no-setters-in-layouters`: flags `:set-position`, `:set-rotation`, `:set-size`, `mark-layout-dirty`, and `mark-measure-dirty` inside functions/forms named `layouter`;
- `layout.owned-child-drop`: flags modules creating retained child `Layout`, child entity, or renderer-owned child without a `drop` path;
- `layout.interactive-context-assertion`: flags interactive widgets using `clickables` or `hoverables` without `assert`.

- [ ] **Step 2: Run the focused test and confirm it fails**

Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-constraints-rules-layout:main
```

Expected: FAIL because `constraints.rules.layout` does not exist.

- [ ] **Step 3: Implement layouter setter rule**

In `constraints/rules/layout.fnl`, implement `layout.no-setters-in-layouters` with family `"layout-rendering"`. Diagnostics must point to the setter call line and use hint `"Inside layouters, assign child layout fields directly instead of calling setters that dirty layout mid-pass."`.

- [ ] **Step 4: Implement owned child drop rule**

Implement `layout.owned-child-drop`:
- detect retained child creation forms containing `Layout`, `LayoutRoot`, `:children`, `:scene-children`, `:scene-objects`, `:scene-terrains`, or renderer child fields;
- require a `drop` definition or returned table `:drop`;
- require child drop evidence with `:drop`, `clear-children`, `drop-children`, or direct iteration calling `:drop` on each child.

- [ ] **Step 5: Implement interactive context assertion rule**

Implement `layout.interactive-context-assertion`:
- detect access to `ctx.clickables`, `ctx.hoverables`, `clickables`, or `hoverables`;
- flag silent guards around missing routing services;
- accept `assert` in the same enclosing function.

- [ ] **Step 6: Register test module and validate**

Add `:tests.test-constraints-rules-layout` to `assets/lua/tests/fast.fnl`, then rerun the command from Step 2.

Expected: PASS.

- [ ] **Step 7: Commit layout constraints**

```bash
git add assets/lua/constraints/rules/layout.fnl assets/lua/tests/test-constraints-rules-layout.fnl assets/lua/tests/fast.fnl
git commit -m "feat(lua): add layout rendering constraints"
```

---

### Task 9: Structure and formatting constraint family

**Files:**
- Create: `assets/lua/constraints/rules/structure.fnl`
- Create: `assets/lua/tests/test-constraints-rules-structure.fnl`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes: fact DB metrics from Task 4 and baseline policy from Task 5.
- Produces:
  ```fennel
  (Structure.rules) ; -> structure/formatting family rules
  ```

Initial thresholds:

```fennel
{:max-nesting-depth 7
 :max-function-length 120
 :max-module-length 1200
 :max-table-literal-size 80
 :max-anonymous-callback-depth 3}
```

- [ ] **Step 1: Write failing structure rule tests**

Create tests proving:
- `structure.max-nesting-depth` flags a function with nesting depth `8`;
- `structure.max-function-length` flags a function with length `121`;
- `structure.max-module-length` flags a module with length `1201`;
- `structure.large-inline-structure` flags a table literal with `81` entries and anonymous callback depth `4`;
- `structure.style-doctrine` flags `let`, new compatibility aliases, and silent fallback forms;
- each rule has a valid source that does not emit diagnostics.

- [ ] **Step 2: Run the focused test and confirm it fails**

Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-constraints-rules-structure:main
```

Expected: FAIL because `constraints.rules.structure` does not exist.

- [ ] **Step 3: Implement metric threshold rules**

In `constraints/rules/structure.fnl`, implement:
- `structure.max-nesting-depth`;
- `structure.max-function-length`;
- `structure.max-module-length`;
- `structure.large-inline-structure`.

Each diagnostic must include `evidence.measure`, `evidence.limit`, and a stable fingerprint based on `constraint-id`, file path, line, and measured construct name.

- [ ] **Step 4: Implement style doctrine rule**

Implement `structure.style-doctrine` to flag:
- `(let ` forms;
- aliases whose keys contain `legacy`, `compat`, or `alias`;
- fallback forms matching `(or required-value fallback-value)` when the same enclosing function does not contain `assert` or `error`.

- [ ] **Step 5: Register test module and validate**

Add `:tests.test-constraints-rules-structure` to `assets/lua/tests/fast.fnl`, then rerun the command from Step 2.

Expected: PASS.

- [ ] **Step 6: Commit structure constraints**

```bash
git add assets/lua/constraints/rules/structure.fnl assets/lua/tests/test-constraints-rules-structure.fnl assets/lua/tests/fast.fnl
git commit -m "feat(lua): add structure constraints"
```

---

### Task 10: Rule registry and default repo execution

**Files:**
- Modify: `assets/lua/constraints/runner.fnl`
- Create: `assets/lua/constraints/rules/init.fnl`
- Create: `assets/lua/tests/test-constraints-default-run.fnl`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes:
  ```fennel
  (Targets.resolve argv env)
  (Source.discover target)
  (Facts.extract files)
  (SceneSandbox.rules)
  (Lifecycle.rules)
  (TestIsolation.rules)
  (LayoutRules.rules)
  (Structure.rules)
  ```
- Produces:
  ```fennel
  (RuleRegistry.all-rules) ; -> complete required rule list
  (Runner.run-target target opts) ; -> aggregate result
  (Runner.main argv) ; default argv runs repo target
  ```

- [ ] **Step 1: Write failing default execution tests**

Create tests proving:
- `RuleRegistry.all-rules` returns all required rule ids from `baseline-data.fnl`;
- `Runner.run-target` discovers files, extracts facts, runs rules, and applies baseline;
- an explicit non-repo file target can run through the same pipeline;
- result diagnostics always include `target.kind` and `target.name`.

- [ ] **Step 2: Run the focused test and confirm it fails**

Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-constraints-default-run:main
```

Expected: FAIL because the registry and `run-target` do not exist.

- [ ] **Step 3: Implement rule registry**

Create `assets/lua/constraints/rules/init.fnl` that requires all rule modules and concatenates their `rules` vectors in deterministic order:
1. Scene/Sandbox;
2. lifecycle;
3. test isolation;
4. layout/rendering;
5. structure/formatting.

- [ ] **Step 4: Implement default target pipeline**

Modify `constraints.runner.fnl`:
- parse CLI args with `Targets.resolve`;
- discover files with `Source.discover`;
- extract facts with `Facts.extract`;
- filter rules by target kind and suite;
- run rules independently;
- apply baseline;
- print one JSON summary.

- [ ] **Step 5: Register test module and validate**

Add `:tests.test-constraints-default-run` to `assets/lua/tests/fast.fnl`, then rerun the command from Step 2.

Expected: PASS.

- [ ] **Step 6: Commit default execution path**

```bash
git add assets/lua/constraints/runner.fnl assets/lua/constraints/rules/init.fnl assets/lua/tests/test-constraints-default-run.fnl assets/lua/tests/fast.fnl
git commit -m "feat(lua): wire default constraint execution"
```

---

### Task 11: Bootstrap reviewed baseline entries

**Files:**
- Modify: `assets/lua/constraints/baseline-data.fnl`

**Interfaces:**
- Consumes: `constraints.runner:main -- --target repo` diagnostics from Tasks 1-10.
- Produces: reviewed baseline entries for existing repo structure/formatting violations only.

- [ ] **Step 1: Run constraints to identify existing violations**

Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m constraints.runner:main -- --target repo
```

Expected: either PASS with no baseline entries needed, or FAIL with existing diagnostics that must be represented explicitly.

- [ ] **Step 2: Add explicit reviewed baseline entries**

For each existing structure/formatting violation that is accepted for bootstrap, add an entry to `assets/lua/constraints/baseline-data.fnl` with this exact reason:

```text
Existing repo violation accepted for experimental constraints bootstrap on 2026-07-27; shrink or remove this entry when the code improves.
```

Do not baseline Scene/Sandbox, lifecycle, layout/rendering, framework failure, interrupted, or baseline-policy diagnostics; fix those rules or production code instead.

- [ ] **Step 3: Verify stale and worsened entries are not introduced**

Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m constraints.runner:main -- --target repo
```

Expected: PASS. If it fails with `baseline.stale`, remove the stale entry. If it fails with `baseline.worsened`, set the entry measure to the current measure only when the current code is the original bootstrap state; otherwise fix the code.

- [ ] **Step 4: Commit baseline data**

```bash
git add assets/lua/constraints/baseline-data.fnl
git commit -m "chore(lua): baseline existing structure constraint findings"
```

---

### Task 12: Blocking Make and CTest integration

**Files:**
- Modify: `Makefile`
- Modify: `CMakeLists.txt`
- Create: `assets/lua/tests/test-constraints-integration-config.fnl`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes: `constraints.runner:main -- --target repo`.
- Produces:
  ```bash
  make constraints
  make test
  ctest -R '^space_experimental_constraints$|^space_fnl_tests$'
  ```

- [ ] **Step 1: Write failing integration config test**

Create `assets/lua/tests/test-constraints-integration-config.fnl` that reads `Makefile` and `CMakeLists.txt` and asserts:
- `Makefile` declares `.PHONY` target `constraints`;
- `make test` depends on `constraints`;
- constraints command includes `SPACE_DISABLE_AUDIO=1`;
- constraints command includes absolute `SPACE_ASSETS_PATH=$(shell pwd)/assets`;
- constraints command includes `FENNEL_PATH`;
- constraints command includes `FENNEL_MACRO_PATH`;
- CMake declares test name `space_experimental_constraints`;
- CMake gives Fennel tests a fixture dependency on `space_experimental_constraints`.

- [ ] **Step 2: Run the focused test and confirm it fails**

Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-constraints-integration-config:main
```

Expected: FAIL because integration is not configured.

- [ ] **Step 3: Add Make target**

Modify `Makefile`:
- add `constraints` to `.PHONY`;
- add target:
  ```make
  constraints: build
	@SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 \
	SPACE_LOG_DIR=/tmp/space/tests/log SPACE_ASSETS_PATH=$(shell pwd)/assets \
	FENNEL_PATH=$(shell pwd)/assets/lua/?.fnl\;$(shell pwd)/assets/lua/?/init.fnl \
	FENNEL_MACRO_PATH=$(shell pwd)/assets/lua/?.fnl\;$(shell pwd)/assets/lua/?/init.fnl \
	./build/space -m constraints.runner:main -- --target repo
  ```
- change `test:` to `test: constraints`.

- [ ] **Step 4: Add blocking CTest fixture**

Modify `CMakeLists.txt` near existing Fennel tests:
- add:
  ```cmake
  add_test(NAME ${PROJECT_NAME}_experimental_constraints
      COMMAND space -m constraints.runner:main -- --target repo
  )
  set_tests_properties(${PROJECT_NAME}_experimental_constraints PROPERTIES
      WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
      FIXTURES_SETUP space_experimental_constraints
  )
  ```
- add `FIXTURES_REQUIRED space_experimental_constraints` to both `${PROJECT_NAME}_fnl_tests` and `${PROJECT_NAME}_fnl_tests_integration`.

- [ ] **Step 5: Register test module and validate**

Add `:tests.test-constraints-integration-config` to `assets/lua/tests/fast.fnl`, then run:

```bash
make cmake
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-constraints-integration-config:main
make constraints
ctest --test-dir build -R '^space_experimental_constraints$|^space_fnl_tests$' --output-on-failure
```

Expected: all commands PASS, and CTest runs `space_experimental_constraints` before `space_fnl_tests`.

- [ ] **Step 6: Commit integration**

```bash
git add Makefile CMakeLists.txt assets/lua/tests/test-constraints-integration-config.fnl assets/lua/tests/fast.fnl
git commit -m "build(lua): block fennel tests on experimental constraints"
```

---

### Task 13: Developer documentation

**Files:**
- Create: `docs/dev/experimental-constraints.md`
- Modify: `docs/dev/index.md`
- Modify: `AGENTS.md`

**Interfaces:**
- Consumes: final CLI and statuses from Tasks 1-12.
- Produces: documented workflow for implementers and reviewers.

- [ ] **Step 1: Write documentation content**

Create `docs/dev/experimental-constraints.md` documenting:
- purpose of the experimental blocking gate;
- `make constraints`;
- `make test` running constraints first;
- result statuses `pass`, `violations`, `fail`, `interrupted`;
- target examples:
  ```bash
  ./build/space -m constraints.runner:main -- --target repo
  ./build/space -m constraints.runner:main -- --target unit --root /path/to/unit-root
  ./build/space -m constraints.runner:main -- --target app --root /path/to/app-scripts
  ./build/space -m constraints.runner:main -- --target files --file /path/to/one.fnl --file /path/to/two.fnl
  ```
- the four families: Scene/Sandbox, lifecycle, layout/rendering, structure/formatting;
- baseline policy and the rule that stale or worsened baseline entries block.

- [ ] **Step 2: Link docs and update agent instructions**

Add the new page to `docs/dev/index.md`. In `AGENTS.md`, update Build/Run/Test guidance so implementers run `make constraints` before focused Fennel tests and understand that `make test` already depends on constraints.

- [ ] **Step 3: Validate docs and commands**

Run:

```bash
rg -n "experimental constraints|make constraints|violations|interrupted" docs/dev/experimental-constraints.md docs/dev/index.md AGENTS.md
make constraints
```

Expected: `rg` finds the documented workflow and `make constraints` PASS.

- [ ] **Step 4: Commit documentation**

```bash
git add docs/dev/experimental-constraints.md docs/dev/index.md AGENTS.md
git commit -m "docs: document experimental constraints workflow"
```

---

## Acceptance Criteria

- `make constraints` exists and exits nonzero for `violations`, `fail`, or `interrupted`.
- `make test` depends on `constraints`.
- CTest target `space_experimental_constraints` runs before `space_fnl_tests` and `space_fnl_tests_integration`.
- `tree-sitter.parse` supports `{:language :fennel}` and reports source locations.
- The runner can analyze repo, user-unit roots, app roots, and explicit files outside `assets/lua/`.
- Static facts include requires, definitions, exports, calls, accesses, mutations, and structure metrics.
- Executable scenario constraints run inside the normal `build/space -m ...` runtime.
- Rule coverage includes Scene/Sandbox, lifecycle, layout/rendering, and structure/formatting families.
- Every rule has at least one valid and one invalid focused test.
- Existing structure violations are represented only by explicit reviewed baseline entries.
- Production modules do not import or call constraint modules.
- `docs/dev/experimental-constraints.md` documents the feature and workflow.

## Validation Ladder

1. Focused implementation tests during tasks:
   ```bash
   SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-tree-sitter-fennel:main
   SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-constraints-runner:main
   SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-constraints-source:main
   SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-constraints-facts:main
   SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-constraints-baseline:main
   SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-constraints-default-run:main
   ```

2. Complete relevant suite:
   ```bash
   make constraints
   SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
   ```

3. Broader final checks justified by build and CTest integration risk:
   ```bash
   make build
   ctest --test-dir build -R '^space_experimental_constraints$|^space_fnl_tests$|^space_fnl_tests_integration$' --output-on-failure
   python3 scripts/ctest-summary.py --test-dir build --output-on-failure -E "^space_fnl_tests_integration$$"
   ```

## Out of Scope

- No general constraint query language.
- No complete Fennel semantic analyzer.
- No macro-expanded analysis.
- No advisory-only mode.
- No production-module annotations for constraints.
- No replacement for human review.
- No replacement for unit or integration tests.
