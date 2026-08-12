# OpenCode Runtime Artifact Access Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce permission friction by allowing the supervisor and explorer to inspect Space-created runtime artifacts needed for internal Space agent debugging while preserving secret protection and role boundaries.

**Architecture:** Update only the supervisor/explorer OpenCode agent permission frontmatter plus prompt guidance, with explicit Space app-dir allows followed by narrower deny rules because OpenCode evaluates the last matching rule. Keep implementer/reviewer external access unchanged. Document the operational boundary in a focused docs/dev note.

**Tech Stack:** OpenCode agent Markdown frontmatter, repository permission checker `scripts/check_opencode_permissions.py`, Space XDG app-dir conventions from `src/appdirs.cpp`.

## Global Constraints

- Changes are `.opencode/agents/**`; supervisor must not edit them directly. Plan will be implemented by implementer then reviewer.
- Do not change `.opencode/opencode.json` unless absolutely necessary; likely not needed.
- No broad home/root access.
- No ask actions.
- Preserve secret protection: deny auth/token/secret/credential/keyring-looking files after broad Space app-dir allows because OpenCode evaluates last matching rule.
- Avoid giving implementer/reviewer external access.
- No build needed unless touching runtime code; runtime code is out of scope.

---

### Task 1: Supervisor and Explorer Runtime Artifact Access

**Files:**
- Modify: `.opencode/agents/supervisor.md`
- Modify: `.opencode/agents/explorer.md`
- Create: `docs/dev/notes/opencode-runtime-artifact-access.md`

**Interfaces:**
- Consumes: OpenCode `permission.external_directory` ordered mapping semantics: last matching rule wins.
- Produces: Supervisor/explorer read/glob/grep/list access to Space runtime artifact scopes:
  - `~/.local/share/space/**`
  - `~/.config/space/**`
  - `~/.cache/space/**`
  - `/tmp/space/**`

- [ ] **Step 1: Update supervisor external_directory mapping.**
  In `.opencode/agents/supervisor.md`, replace the existing `external_directory` block with this ordered mapping:
  ```yaml
  external_directory:
    "*": deny
    "~/space/**": allow
    "~/.local/share/space/**": allow
    "~/.config/space/**": allow
    "~/.cache/space/**": allow
    "/tmp/space/**": allow
    "~/.local/share/space/**/*auth*": deny
    "~/.local/share/space/**/*token*": deny
    "~/.local/share/space/**/*secret*": deny
    "~/.local/share/space/**/*credential*": deny
    "~/.local/share/space/**/*keyring*": deny
    "~/.config/space/**/*auth*": deny
    "~/.config/space/**/*token*": deny
    "~/.config/space/**/*secret*": deny
    "~/.config/space/**/*credential*": deny
    "~/.config/space/**/*keyring*": deny
    "~/.cache/space/**/*auth*": deny
    "~/.cache/space/**/*token*": deny
    "~/.cache/space/**/*secret*": deny
    "~/.cache/space/**/*credential*": deny
    "~/.cache/space/**/*keyring*": deny
    "/tmp/space/**/*auth*": deny
    "/tmp/space/**/*token*": deny
    "/tmp/space/**/*secret*": deny
    "/tmp/space/**/*credential*": deny
    "/tmp/space/**/*keyring*": deny
  ```

- [ ] **Step 2: Add supervisor prompt guidance.**
  In `.opencode/agents/supervisor.md`, extend the `## External Directory Access` section with guidance that these scopes are only for Space-created/Space-used runtime artifacts, especially:
  - `~/.local/share/space/agent-sessions/**`
  - `~/.local/share/space/agent-approvals/**`
  - `~/.local/share/space/agent-opencode/**`
  - `~/.local/share/space/code/**`
  - `~/.cache/space/log/**`
  The guidance must explicitly say not to inspect raw credentials, auth, token, secret, credential, or keyring-looking files.

- [ ] **Step 3: Update explorer external_directory mapping.**
  In `.opencode/agents/explorer.md`, replace the existing `external_directory` block with the same Space app-dir allow/deny mapping from Step 1, except omit `~/space/**`. Explorer should receive only Space runtime artifact scopes:
  ```yaml
  external_directory:
    "*": deny
    "~/.local/share/space/**": allow
    "~/.config/space/**": allow
    "~/.cache/space/**": allow
    "/tmp/space/**": allow
    "~/.local/share/space/**/*auth*": deny
    "~/.local/share/space/**/*token*": deny
    "~/.local/share/space/**/*secret*": deny
    "~/.local/share/space/**/*credential*": deny
    "~/.local/share/space/**/*keyring*": deny
    "~/.config/space/**/*auth*": deny
    "~/.config/space/**/*token*": deny
    "~/.config/space/**/*secret*": deny
    "~/.config/space/**/*credential*": deny
    "~/.config/space/**/*keyring*": deny
    "~/.cache/space/**/*auth*": deny
    "~/.cache/space/**/*token*": deny
    "~/.cache/space/**/*secret*": deny
    "~/.cache/space/**/*credential*": deny
    "~/.cache/space/**/*keyring*": deny
    "/tmp/space/**/*auth*": deny
    "/tmp/space/**/*token*": deny
    "/tmp/space/**/*secret*": deny
    "/tmp/space/**/*credential*": deny
    "/tmp/space/**/*keyring*": deny
  ```

- [ ] **Step 4: Add explorer prompt guidance.**
  In `.opencode/agents/explorer.md`, add a short `## External Runtime Artifacts` section instructing explorer to use the added external scopes only for focused Space runtime debugging, report uncertainties, and avoid raw credential/auth/token/secret/credential/keyring-looking files.

- [ ] **Step 5: Add docs/dev note.**
  Create `docs/dev/notes/opencode-runtime-artifact-access.md` documenting:
  - Linux Space app dirs from `src/appdirs.cpp`.
  - Internal agent artifact subdirs from `assets/lua/main.fnl`: `agent-approvals`, `agent-opencode`, `agent-sessions`, and `code`.
  - Supervisor/explorer may inspect these for debugging.
  - Implementer/reviewer external-directory boundaries remain unchanged.
  - Secret-looking files remain denied after broad Space app-dir allows because last matching rule wins.

- [ ] **Step 6: Validate OpenCode permission policy.**
  Run:
  ```bash
  python3 scripts/check_opencode_permissions.py --repo-root .
  ```
  Expected: JSON output with `"status": "pass"`.

- [ ] **Step 7: Inspect diff for safety invariants.**
  Confirm via diff review that:
  - No `.opencode/opencode.json` changes exist.
  - No implementer/reviewer permissions changed.
  - No `ask` action was added.
  - No broad home/root external allow was added.
  - Secret-looking deny rules appear after Space app-dir allow rules.

**Acceptance Criteria:**
- Supervisor can inspect Space runtime artifact trees under data/config/cache/tmp Space scopes without permission prompts.
- Explorer can inspect the same runtime artifact trees for focused investigation.
- Secret/auth/token/credential/keyring-looking paths under those scopes are denied by later matching rules.
- Implementer and reviewer external-directory permissions remain unchanged.
- `python3 scripts/check_opencode_permissions.py --repo-root .` passes.
- OpenCode users are told to restart OpenCode for agent permission changes to take effect.

**Validation Ladder:**
1. Focused config safety check: `python3 scripts/check_opencode_permissions.py --repo-root .`.
2. Focused diff review of `.opencode/agents/supervisor.md`, `.opencode/agents/explorer.md`, and `docs/dev/notes/opencode-runtime-artifact-access.md`.
3. No `make build`, Fennel checks, or runtime tests are required because this plan changes only OpenCode agent configuration and docs.
4. PR CI is the full integration gate.

**Out of Scope:**
- Changes to `.opencode/opencode.json`.
- Changes to Space runtime code, app-dir resolution, or artifact storage locations.
- Granting implementer, reviewer, planner, or capability agents new external-directory access.
- Access to raw credentials, auth files, tokens, secrets, credential stores, or keyring-looking files.
- Broad home/root external access or any permission `ask` action.
