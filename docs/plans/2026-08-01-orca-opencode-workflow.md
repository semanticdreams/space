# Orca OpenCode Workflow Documentation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create the canonical developer documentation page for Space’s Orca/OpenCode agent workflow and link it from existing developer docs indexes.

**Architecture:** This is a documentation-only change. Add one VitePress Markdown feature page at the sidebar target that already exists, then add discoverability links from the developer feature indexes while leaving docs site configuration unchanged.

**Tech Stack:** Markdown, VitePress, npm docs scripts, official Orca documentation links.

## Global Constraints

- Target plan path: `docs/plans/2026-08-01-orca-opencode-workflow.md`.
- Create `docs/dev/features/opencode-agent-workflow.md`.
- Modify `docs/dev/features/index.md`.
- Modify `docs/dev/index.md`.
- Leave `docs/.vitepress/config.mts` unchanged.
- Include official Orca links exactly:
  - `https://www.onorca.dev/docs/ways-to-run`
  - `https://www.onorca.dev/docs/ssh`
  - `https://www.onorca.dev/docs/remote-servers`
- Present local Orca plus remote SSH as one possible supported setup, not the only supported setup.
- Include the alternative setup where Orca runs entirely on the remote VM and local Orca is used only to view or connect to it.
- Include Space-specific workflow guidance for `AGENTS.md`, repo-local `.opencode/**`, restarting OpenCode after `.opencode/**` changes, validation expectations, and branch/PR policy.
- Explicitly exclude laptop-specific notify plugin setup, the obsolete separate `opencode-config` repository, and `auth.json` copying instructions.
- Out of scope: editing `.opencode/**`, changing runtime code, changing tests, changing package dependencies, changing docs site configuration, or documenting credential migration.
- Validation ladder:
  1. Focused text review of required links, inclusions, exclusions, and modified file list.
  2. Complete relevant suite: `cd docs && npm run docs:build`.
  3. Broader final check justified by docs-site risk: verify `docs/.vitepress/config.mts` has no diff.
- HUMAN_DECISION_REQUIRED: none.

---

### Task 1: Create the OpenCode Agent Workflow Feature Page

**Files:**
- Create: `docs/dev/features/opencode-agent-workflow.md`
- Test: focused text review of `docs/dev/features/opencode-agent-workflow.md`

**Interfaces:**
- Consumes: committed spec `docs/specs/2026-08-01-orca-opencode-workflow-design.md`
- Produces: canonical documentation page at `/dev/features/opencode-agent-workflow`

- [ ] **Step 1: Create the page with the required title and purpose**

Create `docs/dev/features/opencode-agent-workflow.md` with this top-level heading:

```markdown
# OpenCode Agent Workflow
```

The opening paragraph must state that this page documents Space’s shared Orca/OpenCode workflow for collaborators using the repo-local configuration.

- [ ] **Step 2: Add an official Orca documentation section**

Add a section named:

```markdown
## Official Orca documentation
```

Include links to:

```markdown
- [Ways to run Orca](https://www.onorca.dev/docs/ways-to-run)
- [Orca SSH](https://www.onorca.dev/docs/ssh)
- [Orca remote servers](https://www.onorca.dev/docs/remote-servers)
```

- [ ] **Step 3: Add supported setup options**

Add a section named:

```markdown
## Supported setups
```

It must describe both supported arrangements:

- Local Orca connecting to a remote SSH checkout of Space.
- Orca running on the remote VM, with local Orca used only to view or connect to that remote session.

The text must make clear that local Orca plus remote SSH is one possible setup, not a project requirement.

- [ ] **Step 4: Add the local Orca plus remote SSH checklist**

Add a section named:

```markdown
## Local Orca plus remote SSH checklist
```

Include checklist items covering:

- Remote VM can be reached with SSH.
- GitHub SSH access works from the remote VM, for example by testing `ssh -T git@github.com`.
- The Space repository is cloned on the remote VM.
- The worker opens the Space checkout through Orca’s SSH/remote-server workflow.
- The worker relies on the checked-out repository’s `AGENTS.md` and `.opencode/**`.

Do not include private host paths, machine-specific usernames, or credential-copy instructions.

- [ ] **Step 5: Add the remote-VM Orca alternative**

Add a section named:

```markdown
## Remote-VM Orca alternative
```

Explain that collaborators may run Orca entirely on the remote VM when that better matches their environment, and use local Orca only as a viewer/connector. Link this back to Orca’s remote-server documentation.

- [ ] **Step 6: Add Space-specific workflow expectations**

Add a section named:

```markdown
## Space workflow expectations
```

Include these points:

- `AGENTS.md` is the always-on repository guidance.
- `.opencode/**` is the repo-local source for Space agents, skills, and OpenCode configuration.
- OpenCode must be restarted after changes to `.opencode/opencode.json`, `.opencode/agents/**`, or `.opencode/skills/**`.
- Agents should follow repository validation expectations from `AGENTS.md`.
- For full Space validation, cite:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
```

- Fennel-facing work must use the project-native Fennel validation ladder from `AGENTS.md`.
- Required validation failures should be treated as debugging tasks rather than bypassed.

- [ ] **Step 7: Add branch and PR policy**

Add a section named:

```markdown
## Branch and pull request policy
```

Document:

- Pull requests target `main`.
- Final validation and diff/base checks use `origin/main`, not local `main`.
- After implementation is reviewed, committed, green, and the tree is clean, the default action is to push the branch and create a pull request targeting `main`.
- Do not push directly to `main`.

- [ ] **Step 8: Add explicit exclusions**

Add a section named:

```markdown
## Exclusions
```

State that the shared Space guide intentionally does not document:

- laptop-specific notify plugin setup;
- the obsolete separate `opencode-config` repository as an active requirement;
- copying, migrating, or sharing `auth.json`.

- [ ] **Step 9: Focused page self-review**

Review `docs/dev/features/opencode-agent-workflow.md` and confirm:

- All three official Orca links are present.
- Both supported setup options are present.
- The page says repo-local `.opencode/**` is canonical for this repository.
- Restart-after-`.opencode/**` guidance is present.
- Validation and branch/PR policy are present.
- Excluded items appear only as exclusions, not setup instructions.

---

### Task 2: Add Developer Docs Index Links

**Files:**
- Modify: `docs/dev/features/index.md`
- Modify: `docs/dev/index.md`
- Test: focused text review of both index files

**Interfaces:**
- Consumes: page produced by Task 1 at `docs/dev/features/opencode-agent-workflow.md`
- Produces: discoverability links from developer documentation indexes

- [ ] **Step 1: Add the feature index link**

In `docs/dev/features/index.md`, add this bullet near the other feature pages:

```markdown
- [OpenCode Agent Workflow](./opencode-agent-workflow)
```

- [ ] **Step 2: Add the developer index link**

In `docs/dev/index.md`, under `## Feature Pages`, add this bullet near the other feature pages:

```markdown
- [OpenCode Agent Workflow](/dev/features/opencode-agent-workflow)
```

- [ ] **Step 3: Confirm docs site config is not edited**

Check that `docs/.vitepress/config.mts` has not been modified. The existing sidebar link already targets `/dev/features/opencode-agent-workflow`, so no config change is needed.

- [ ] **Step 4: Focused index self-review**

Confirm:

- Both index links use the same title: `OpenCode Agent Workflow`.
- Both links point to `opencode-agent-workflow`.
- No new VitePress sidebar entry was added.

---

### Task 3: Documentation Validation

**Files:**
- Test: `docs/dev/features/opencode-agent-workflow.md`
- Test: `docs/dev/features/index.md`
- Test: `docs/dev/index.md`
- Test: `docs/.vitepress/config.mts`

**Interfaces:**
- Consumes: documentation changes from Tasks 1 and 2
- Produces: validated documentation-only change ready for review

- [ ] **Step 1: Run focused text review**

Run:

```bash
rg -n "ways-to-run|/ssh|remote-servers|AGENTS.md|\\.opencode|restart|origin/main|auth\\.json|opencode-config|notify" docs/dev/features/opencode-agent-workflow.md docs/dev/features/index.md docs/dev/index.md
```

Expected:

- Required Orca links are found.
- `AGENTS.md`, `.opencode`, restart, validation, and `origin/main` guidance are found.
- `auth.json`, `opencode-config`, and notify plugin appear only in the exclusions section.

- [ ] **Step 2: Verify changed-file scope**

Run:

```bash
git diff --name-only
```

Expected implementation files only:

```text
docs/dev/features/opencode-agent-workflow.md
docs/dev/features/index.md
docs/dev/index.md
```

Plan/spec files may already exist from planning commits, but this documentation implementation must not modify runtime code, package files, `.opencode/**`, or docs site configuration.

- [ ] **Step 3: Verify VitePress config is unchanged**

Run:

```bash
git diff -- docs/.vitepress/config.mts
```

Expected: no output.

- [ ] **Step 4: Build the docs site**

Run:

```bash
cd docs && npm run docs:build
```

Expected: command exits successfully and VitePress build completes without broken-link or build errors.

- [ ] **Step 5: Final acceptance review**

Confirm the observable acceptance criteria:

- `/dev/features/opencode-agent-workflow` has a source page.
- `docs/dev/features/index.md` links to it.
- `docs/dev/index.md` links to it.
- `docs/.vitepress/config.mts` remains unchanged.
- The page contains the required official Orca links, supported setup options, Space workflow guidance, validation expectations, branch/PR policy, and explicit exclusions.
