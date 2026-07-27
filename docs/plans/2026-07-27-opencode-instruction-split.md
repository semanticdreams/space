# OpenCode Instruction Split Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor Space project instructions into a slim always-on `AGENTS.md`, project-specific OpenCode skills, and small role-agent routing guidance.

**Architecture:** Keep durable cross-tool facts in `AGENTS.md`, move detailed Space domain guidance into triggerable `.opencode/skills/space-*` skill files, and add minimal routing hints to role agents. Canonical architecture detail remains in `docs/dev/**`; skills and `AGENTS.md` reference those docs instead of duplicating them.

**Tech Stack:** Markdown, OpenCode project agents/skills, repository validation with `python3`, `rg`, `git diff --check`, `make test`.

## Global Constraints

- `AGENTS.md` remains the concise, durable source of project facts that every agent and tool should see: repository structure, canonical build/test commands, branch/integration policy, high-risk project rules, and pointers to deeper docs.
- `.opencode/agents/**` remains mostly role and permission configuration: supervisor coordination, implementer/reviewer discipline, model choices, and safe tool behavior.
- `.opencode/skills/**` gains project-specific, task-triggered guidance for Space domains that are too detailed to keep always loaded.
- `docs/dev/**` remains the human-readable canonical architecture reference. Project skills should reference docs instead of copying long sections.
- Do not create a separate skill for every subsystem yet.
- `AGENTS.md` should remain useful outside OpenCode, but it should not duplicate full docs/dev pages or long skill bodies.
- Keep role agents generic by default.
- Do not create new subagents initially.
- Prefer references to `docs/dev/**` over copying full architecture documents into skills.
- If guidance exists in both `AGENTS.md` and a skill, one should be a short pointer and the other should hold the actionable detail.
- Project skills must have precise descriptions so they trigger only on relevant tasks.
- Config changes under `.opencode/**` still go through implementer → reviewer → pass.
- After `.opencode` changes, users must restart OpenCode for the new config to load.
- No production or test code should change.

**Invariants and compatibility requirements:**
- Existing agent frontmatter, model choices, modes, and permissions stay valid unless explicitly listed in this plan.
- Existing generic workflow skills remain generic and unchanged.
- New skill folder names must match their `name:` frontmatter exactly.
- No `opencode.json` change is required unless an implementer discovers the current project configuration cannot load `.opencode/skills/**`; if so, stop and report `HUMAN_DECISION_REQUIRED`.
- `AGENTS.md` must retain canonical build/test/run commands and branch/commit conventions.
- `docs/dev/features/development-tooling.md` is the docs/dev page for documenting the instruction-split workflow change.

**Acceptance criteria:**
- `AGENTS.md` has fewer lines than the current 145-line version and contains only summaries, commands, high-risk rules, and references.
- `.opencode/skills/space-fennel-ui/SKILL.md`, `.opencode/skills/space-graph-doctrine/SKILL.md`, and `.opencode/skills/space-testing-runtime/SKILL.md` exist with valid OpenCode skill frontmatter.
- New skills reference canonical docs and avoid copying long architecture prose.
- `.opencode/agents/supervisor.md` routes Fennel UI, graph doctrine, and testing/runtime tasks to the new skills.
- `.opencode/agents/planner.md` keeps plans disciplined about `docs/dev` updates for behavior, architecture, workflow, or operational-assumption changes.
- No files under `src/`, `apps/`, `assets/`, `tests/`, `scripts/`, `CMakeLists.txt`, or `Makefile` are changed.

**Validation ladder:**
- Focused implementation validation: skill frontmatter/path checks, canonical doc-reference checks, stale/duplicated-detail grep checks, and `git diff --check`.
- Complete relevant suite: run the full static validation block across `AGENTS.md`, `.opencode/skills/**`, `.opencode/agents/supervisor.md`, `.opencode/agents/planner.md`, and `docs/dev/features/development-tooling.md`.
- Broader final check: run the full repo test command once at final validation only, because production/test code should not change but the user explicitly requested final full-suite validation.

**Out of scope:**
- Production code, test code, CMake, Makefile, asset, script, or runtime behavior changes.
- New subagents.
- Broad rewrites of generic role agents or generic workflow skills.
- Copying full `docs/dev/**` architecture pages into OpenCode skill files.
- Adding subsystem-specific skills beyond the three specified Space project skills.

---

### Task 1: Project-Specific Space Skills

**Files:**
- Create: `.opencode/skills/space-fennel-ui/SKILL.md`
- Create: `.opencode/skills/space-graph-doctrine/SKILL.md`
- Create: `.opencode/skills/space-testing-runtime/SKILL.md`

**Interfaces:**
- Consumes: Existing OpenCode skill file convention: `.opencode/skills/<skill-name>/SKILL.md` with `name:` and `description:` frontmatter.
- Produces: Skills named `space-fennel-ui`, `space-graph-doctrine`, and `space-testing-runtime` for later references from `AGENTS.md` and `.opencode/agents/supervisor.md`.

- [ ] **Step 1: Inspect existing skill format**

Run:

```bash
sed -n '1,30p' .opencode/skills/test-driven-development/SKILL.md
```

Expected: frontmatter includes `name:` and `description:`, followed by a Markdown heading.

- [ ] **Step 2: Create `space-fennel-ui` skill**

Create `.opencode/skills/space-fennel-ui/SKILL.md` with:
- `name: space-fennel-ui`
- Description: `Use when editing or designing Space Fennel widgets, layout, rendering adapters, interaction widgets, widget lifecycle, or widget tests.`
- Body sections:
  - `# Space Fennel UI`
  - `## Use When`
  - `## Canonical References`
  - `## Required Reminders`
  - `## Avoid`
- Required references:
  - `docs/dev/fennel/style.md`
  - `docs/dev/lifecycle-invariants.md`
  - `docs/dev/widget-ownership-and-teardown.md`
- Required compact reminders:
  - Widget constructors return build closures.
  - Builders receive renderer/build context and instantiate children with that context.
  - Widgets own explicit `Layout` objects.
  - Composite widgets own and drop their direct child widgets.
  - Directly write child layout transforms during layout passes instead of calling dirtying setters.
  - Mark the shallowest appropriate layout dirty.
  - Assert on missing required context instead of silently falling back.
  - Prefer project Fennel idioms: `local` over `let`, multi-branch `if`, factory functions over `.new`.

- [ ] **Step 3: Create `space-graph-doctrine` skill**

Create `.opencode/skills/space-graph-doctrine/SKILL.md` with:
- `name: space-graph-doctrine`
- Description: `Use when editing Space graph nodes, graph maps, graph views, graph persistence, graph topology, graph key loaders, or graph terminology.`
- Body sections:
  - `# Space Graph Doctrine`
  - `## Use When`
  - `## Canonical References`
  - `## Required Doctrine`
  - `## Terminology`
- Required references:
  - `docs/dev/notes/graph.md`
  - `docs/dev/graph-maps.md`
- Required compact reminders:
  - The graph is an exposure/adaptor layer, not the owner of domain objects.
  - Graph core persists topology only.
  - Owning systems persist domain data.
  - Key loaders adapt owning stores/systems into graph node adapters.
  - `GraphMap` owns interaction context over shared graph-addressable objects.
  - Avoid forbidden terminology by using the canonical terms from `docs/dev/notes/graph.md`.

- [ ] **Step 4: Create `space-testing-runtime` skill**

Create `.opencode/skills/space-testing-runtime/SKILL.md` with:
- `name: space-testing-runtime`
- Description: `Use when running, adding, or debugging Space tests, E2E snapshots, remote-control debugging, profiling, build commands, or runtime harnesses.`
- Body sections:
  - `# Space Testing Runtime`
  - `## Use When`
  - `## Canonical Commands`
  - `## Runtime Test Environment`
  - `## E2E Snapshots`
  - `## Remote Control And Profiling`
- Required references:
  - `AGENTS.md`
  - `docs/dev/features/development-tooling.md`
- Required compact reminders:
  - `AGENTS.md` is the canonical source for build/test command spellings and timeout expectations.
  - Use absolute `SPACE_ASSETS_PATH=$(pwd)/assets` for direct Lua/Fennel test runs.
  - Default full suite is `SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test`.
  - E2E snapshots use `make test-e2e`, goldens live under `assets/lua/tests/data/snapshots/`, and PNGs must be visually inspected.
  - Remote-control debugging uses the running app endpoint and `tools.remote-control-client`.
  - Profilers run through `make prof target=<name>`.

- [ ] **Step 5: Validate new skill frontmatter and canonical references**

Run:

```bash
python3 - <<'PY'
from pathlib import Path

skills = {
    "space-fennel-ui": [
        "docs/dev/fennel/style.md",
        "docs/dev/lifecycle-invariants.md",
        "docs/dev/widget-ownership-and-teardown.md",
    ],
    "space-graph-doctrine": [
        "docs/dev/notes/graph.md",
        "docs/dev/graph-maps.md",
    ],
    "space-testing-runtime": [
        "AGENTS.md",
        "docs/dev/features/development-tooling.md",
    ],
}

for name, refs in skills.items():
    path = Path(".opencode/skills") / name / "SKILL.md"
    assert path.is_file(), f"missing {path}"
    text = path.read_text()
    assert text.startswith("---\n"), f"{path}: missing frontmatter"
    parts = text.split("---", 2)
    assert len(parts) == 3, f"{path}: malformed frontmatter"
    head = parts[1]
    body = parts[2].lstrip()
    assert f"name: {name}" in head, f"{path}: name mismatch"
    desc = [line for line in head.splitlines() if line.startswith("description: ")]
    assert desc, f"{path}: missing description"
    assert len(desc[0].split(":", 1)[1].strip()) >= 40, f"{path}: description too vague"
    assert "Use when" in desc[0] or "Use ONLY when" in desc[0], f"{path}: description lacks trigger"
    assert body.startswith("# "), f"{path}: missing top-level heading"
    for ref in refs:
        assert ref in text, f"{path}: missing reference {ref}"
        assert Path(ref).exists(), f"{path}: stale reference {ref}"
PY
```

Expected: command exits successfully with no output.

- [ ] **Step 6: Check for accidental long-form docs copies in skills**

Run:

```bash
python3 - <<'PY'
from pathlib import Path

limits = {
    ".opencode/skills/space-fennel-ui/SKILL.md": 120,
    ".opencode/skills/space-graph-doctrine/SKILL.md": 100,
    ".opencode/skills/space-testing-runtime/SKILL.md": 120,
}

for file_name, max_lines in limits.items():
    lines = Path(file_name).read_text().splitlines()
    assert len(lines) <= max_lines, f"{file_name} is {len(lines)} lines; expected <= {max_lines}"
PY
```

Expected: command exits successfully with no output.

- [ ] **Step 7: Commit Task 1 after review passes**

Run after implementer → reviewer → pass:

```bash
git add .opencode/skills/space-fennel-ui/SKILL.md \
        .opencode/skills/space-graph-doctrine/SKILL.md \
        .opencode/skills/space-testing-runtime/SKILL.md
git commit -m "docs(opencode): add Space project skills"
```

---

### Task 2: Slim Always-On Project Instructions

**Files:**
- Modify: `AGENTS.md`
- Modify: `docs/dev/features/development-tooling.md`

**Interfaces:**
- Consumes: Skill names produced by Task 1: `space-fennel-ui`, `space-graph-doctrine`, `space-testing-runtime`.
- Produces: A concise `AGENTS.md` that remains useful outside OpenCode and points OpenCode users toward the project skills and canonical docs.

- [ ] **Step 1: Record current `AGENTS.md` size**

Run:

```bash
wc -l AGENTS.md
```

Expected before edits: `145 AGENTS.md`.

- [ ] **Step 2: Reshape `AGENTS.md` around always-on facts**

Modify `AGENTS.md` so it keeps these concise sections:
- `# Repository Guidelines`
- Quality/urgency expectations from the current file.
- `## Branch Convention`
- `## Project Structure & Modules`
- `## OpenAI API Docs`
- `## Project-Specific OpenCode Skills`
- `## Build, Run & Test`
- `## Coding Style & High-Risk Rules`
- `## Commit Conventions`
- `## Assets & Configuration Tips`

Required `Project-Specific OpenCode Skills` bullets:
- Use `space-fennel-ui` for Fennel widgets, layout, rendering adapters, interaction widgets, widget lifecycle, or widget tests.
- Use `space-graph-doctrine` for graph nodes, graph maps, graph views, graph persistence/topology, key loaders, or graph terminology.
- Use `space-testing-runtime` for tests, E2E snapshots, remote-control debugging, profiling, build commands, or runtime harnesses.

Required retained command facts:
- `make cmake`
- `make build`
- `make run`
- `make test`
- `python3 scripts/ctest-summary.py --test-dir build --output-on-failure`
- `SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test`
- Build timeout guidance for `make build` and `make cmake`.
- E2E command pointer: `SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test-e2e`.

Required retained high-risk rules:
- No silent failures or quiet fallbacks for required data/bindings.
- Fennel classes construct `self` in a final literal.
- Use `local` instead of `let`.
- Use factory functions instead of constructors/`.new`.
- Preserve canonical option keys; do not add legacy aliases unless explicitly requested.
- Use `assets/lua/json-utils.fnl` for atomic JSON writes.

- [ ] **Step 3: Remove long domain-detail duplication from `AGENTS.md`**

Delete or condense the current long sections for:
- Fennel widget builder/layout/dirt details.
- Lua/Fennel binding details beyond short high-risk reminders.
- Graph doctrine details beyond a short pointer.
- E2E snapshot mechanics beyond canonical command/pointer.
- Profiling mechanics beyond canonical command/pointer.
- Lua/Fennel test harness internals beyond command/pointer.

- [ ] **Step 4: Document the instruction split in `docs/dev/features/development-tooling.md`**

Add one concise design bullet under the existing `## Design` list:
- OpenCode project guidance uses `AGENTS.md` for always-on repository facts and `.opencode/skills/space-*` for triggerable Space domain guidance; users must restart OpenCode after `.opencode/**` changes.

Do not expand this into a full OpenCode manual.

- [ ] **Step 5: Validate `AGENTS.md` is shorter and points to skills/docs**

Run:

```bash
python3 - <<'PY'
from pathlib import Path

lines = Path("AGENTS.md").read_text().splitlines()
assert len(lines) < 145, f"AGENTS.md should be shorter than 145 lines, got {len(lines)}"
text = "\n".join(lines)
for needle in [
    "space-fennel-ui",
    "space-graph-doctrine",
    "space-testing-runtime",
    "docs/dev/fennel/style.md",
    "docs/dev/notes/graph.md",
    "docs/dev/features/development-tooling.md",
    "make cmake",
    "make build",
    "make test",
    "SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test",
]:
    assert needle in text, f"AGENTS.md missing {needle}"
PY
```

Expected: command exits successfully with no output.

- [ ] **Step 6: Validate moved details are not still duplicated in `AGENTS.md`**

Run:

```bash
if rg -n "Each widget module exports|When propagating transforms inside a layouter|Dirt rules:|All flamegraph profilers live|When creating or debugging snapshots" AGENTS.md; then
    echo "AGENTS.md still contains moved long-form detail" >&2
    exit 1
fi
```

Expected: no matches.

- [ ] **Step 7: Validate development tooling doc mentions OpenCode restart**

Run:

```bash
rg -n "OpenCode project guidance|AGENTS.md|\.opencode/skills/space-\*|restart OpenCode" docs/dev/features/development-tooling.md
```

Expected: matches the new concise design bullet.

- [ ] **Step 8: Commit Task 2 after review passes**

Run after implementer → reviewer → pass:

```bash
git add AGENTS.md docs/dev/features/development-tooling.md
git commit -m "docs(opencode): slim always-on project guidance"
```

---

### Task 3: Role-Agent Routing Guidance

**Files:**
- Modify: `.opencode/agents/supervisor.md`
- Modify: `.opencode/agents/planner.md`

**Interfaces:**
- Consumes: Skill names produced by Task 1 and `docs/dev` documentation discipline from Task 2.
- Produces: Minimal role-agent routing guidance that makes project skills discoverable without embedding Space domain doctrine in generic agents.

- [ ] **Step 1: Add project skill routing to supervisor**

Modify `.opencode/agents/supervisor.md` under `## Skill Enforcement` with a short subsection named `## Space Project Skill Routing` or equivalent.

Required routing bullets:
- If a request touches Fennel widgets, layout, rendering adapters, interaction widgets, widget lifecycle, or widget tests, invoke `space-fennel-ui` before planning or implementation.
- If a request touches graph nodes, graph maps, graph views, graph persistence/topology, key loaders, or graph terminology, invoke `space-graph-doctrine` before planning or implementation.
- If a request touches Space tests, E2E snapshots, remote-control debugging, profiling, build commands, or runtime harnesses, invoke `space-testing-runtime` before planning or implementation.
- Keep process skills first when they apply; do not invoke project skills for incidental overlap.

Do not change supervisor permissions, mode, model, or edit allowlist.

- [ ] **Step 2: Add Space docs/dev planning discipline to planner**

Modify `.opencode/agents/planner.md` rules to make the existing docs/dev requirement explicit for Space:
- Plans that change behavior, architecture, workflows, or operational assumptions must name the exact `docs/dev/**` page to create or update.
- If no appropriate docs/dev page exists, the plan must include creating a minimal focused page under `docs/dev/features/` or `docs/dev/notes/`.
- If the change is documentation/config only and existing docs/dev pages remain canonical, the plan must state why no additional docs/dev page is needed.

Do not add Space domain implementation rules to planner.

- [ ] **Step 3: Validate agent routing references exist**

Run:

```bash
rg -n "space-fennel-ui|space-graph-doctrine|space-testing-runtime" .opencode/agents/supervisor.md
rg -n "docs/dev|behavior, architecture, workflows, or operational assumptions|docs/dev/features|docs/dev/notes" .opencode/agents/planner.md
```

Expected: supervisor references all three project skills; planner references docs/dev planning discipline.

- [ ] **Step 4: Validate role agents did not absorb long Space doctrine**

Run:

```bash
if rg -n "builder closures|Dirt rules:|Graph nodes are lightweight adapters|All flamegraph profilers live|When creating or debugging snapshots" .opencode/agents/supervisor.md .opencode/agents/planner.md; then
    echo "Role agents contain long Space domain detail" >&2
    exit 1
fi
```

Expected: no matches.

- [ ] **Step 5: Validate modified agent frontmatter still has required fields**

Run:

```bash
python3 - <<'PY'
from pathlib import Path

for path_name in [".opencode/agents/supervisor.md", ".opencode/agents/planner.md"]:
    path = Path(path_name)
    text = path.read_text()
    assert text.startswith("---\n"), f"{path}: missing frontmatter"
    parts = text.split("---", 2)
    assert len(parts) == 3, f"{path}: malformed frontmatter"
    head = parts[1]
    for field in ["description:", "mode:", "model:", "permission:"]:
        assert field in head, f"{path}: missing {field}"
PY
```

Expected: command exits successfully with no output.

- [ ] **Step 6: Commit Task 3 after review passes**

Run after implementer → reviewer → pass:

```bash
git add .opencode/agents/supervisor.md .opencode/agents/planner.md
git commit -m "docs(opencode): route Space project skills"
```

---

### Task 4: Final Static and Repo Validation

**Files:**
- Test: `AGENTS.md`
- Test: `.opencode/skills/space-fennel-ui/SKILL.md`
- Test: `.opencode/skills/space-graph-doctrine/SKILL.md`
- Test: `.opencode/skills/space-testing-runtime/SKILL.md`
- Test: `.opencode/agents/supervisor.md`
- Test: `.opencode/agents/planner.md`
- Test: `docs/dev/features/development-tooling.md`

**Interfaces:**
- Consumes: All files produced or modified by Tasks 1–3.
- Produces: Final validation evidence that the instruction split is complete, static config is sane, no production/test code changed, and the full repo suite still passes.

- [ ] **Step 1: Run complete skill validation**

Run:

```bash
python3 - <<'PY'
from pathlib import Path

skills = {
    "space-fennel-ui": [
        "docs/dev/fennel/style.md",
        "docs/dev/lifecycle-invariants.md",
        "docs/dev/widget-ownership-and-teardown.md",
    ],
    "space-graph-doctrine": [
        "docs/dev/notes/graph.md",
        "docs/dev/graph-maps.md",
    ],
    "space-testing-runtime": [
        "AGENTS.md",
        "docs/dev/features/development-tooling.md",
    ],
}

for name, refs in skills.items():
    path = Path(".opencode/skills") / name / "SKILL.md"
    assert path.is_file(), f"missing {path}"
    text = path.read_text()
    assert text.startswith("---\n"), f"{path}: missing frontmatter"
    parts = text.split("---", 2)
    assert len(parts) == 3, f"{path}: malformed frontmatter"
    head = parts[1]
    assert f"name: {name}" in head, f"{path}: name mismatch"
    desc = [line for line in head.splitlines() if line.startswith("description: ")]
    assert desc, f"{path}: missing description"
    assert len(desc[0].split(":", 1)[1].strip()) >= 40, f"{path}: description too vague"
    for ref in refs:
        assert ref in text, f"{path}: missing reference {ref}"
        assert Path(ref).exists(), f"{path}: stale reference {ref}"
PY
```

Expected: command exits successfully with no output.

- [ ] **Step 2: Run duplication and stale-path grep checks**

Run:

```bash
if rg -n "Each widget module exports|When propagating transforms inside a layouter|Dirt rules:|All flamegraph profilers live|When creating or debugging snapshots" AGENTS.md; then
    echo "AGENTS.md still contains moved long-form detail" >&2
    exit 1
fi

rg -n "space-fennel-ui|space-graph-doctrine|space-testing-runtime" AGENTS.md .opencode/agents/supervisor.md
rg -n "docs/dev/fennel/style.md|docs/dev/lifecycle-invariants.md|docs/dev/widget-ownership-and-teardown.md|docs/dev/notes/graph.md|docs/dev/graph-maps.md|docs/dev/features/development-tooling.md" AGENTS.md .opencode/skills/space-*/SKILL.md
```

Expected: first block has no moved-detail matches; later `rg` commands find all required skill and docs references.

- [ ] **Step 3: Verify no production or test code changed**

Run:

```bash
BASE=$(git merge-base HEAD main)
git diff --name-only "$BASE"..HEAD -- src/ apps/ assets/ tests/ scripts/ CMakeLists.txt Makefile
```

Expected: no output.

- [ ] **Step 4: Run whitespace/conflict-marker validation**

Run:

```bash
BASE=$(git merge-base HEAD main)
git diff --check "$BASE"..HEAD
```

Expected: no output.

- [ ] **Step 5: Run full repo test once as final validation**

Run with a generous timeout:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
```

Expected: full registered test suite passes.

- [ ] **Step 6: Confirm OpenCode restart guidance is visible**

Run:

```bash
rg -n "restart OpenCode|restart opencode|Restart OpenCode" AGENTS.md docs/dev/features/development-tooling.md .opencode/skills/space-*/SKILL.md
```

Expected: at least one user-visible reminder says OpenCode must be restarted after `.opencode/**` changes.

- [ ] **Step 7: Confirm clean working tree**

Run:

```bash
git status --short
```

Expected: no output.
