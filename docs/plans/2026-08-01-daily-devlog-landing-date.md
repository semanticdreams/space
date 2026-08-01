# Daily Devlog Landing-Date Attribution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Update the daily devlog automation process so devlog entries attribute work by when it lands on `origin/main`, not by feature-branch author or commit dates.

**Architecture:** This is a documentation-and-process correction pinned by the existing docs script test suite. Update the repo-owned OpenCode skill as the operational contract, update the existing developer note as the human-facing reference, and extend `docs/scripts/test-opencode-automation-config.mjs` so future wording cannot regress to ambiguous commit-date behavior.

**Tech Stack:** Markdown, OpenCode project skills, Node.js ESM, `node:test`, VitePress docs scripts.

## Global Constraints

- Target plan path: `docs/plans/2026-08-01-daily-devlog-landing-date.md`.
- Modify `.opencode/skills/daily-devlog-automation/SKILL.md`.
- Modify `docs/dev/notes/daily-devlog-automation.md`.
- Modify `docs/scripts/test-opencode-automation-config.mjs`.
- The skill should explicitly instruct agents to inspect `origin/main` mainline or first-parent history for changes that landed since the latest devlog entry or recent day boundary.
- The automation must describe work on the day it becomes part of `origin/main`, not on the day a feature-branch commit was authored.
- This remains a documentation-and-process correction rather than a new analyzer script.
- Existing devlog index generation remains unchanged.
- The entry stays a single narrative paragraph with the existing frontmatter and date heading.
- Inline Markdown links are allowed when they point to relevant docs, notes, plans, specs, or feature pages and improve reader context.
- Link lists, bullet lists, headings, raw file lists, commit hashes, author lists, and commit-summary prose remain forbidden.
- The compression pass should make the final paragraph denser than the full report without deleting important context.
- If `origin/main` cannot be fetched or inspected, the automation should fail closed rather than guessing from local branch history or commit dates.
- If the evidence is ambiguous, the run should leave a BLOCKED summary identifying the missing mainline/merge information.
- Do not add npm dependencies; use existing Node.js and VitePress tooling only.
- Do not change `.opencode/opencode.json`, `.opencode/agents/**`, GitHub workflows, devlog index generators, runtime code, Fennel files, or generated journal/devlog indexes.
- The existing `docs/dev/notes/daily-devlog-automation.md` remains the canonical `docs/dev/**` page for this workflow; no new docs/dev page is needed.
- OpenCode users must restart OpenCode/Orca after `.opencode/**` changes so the updated skill is loaded.
- Supervisor/planning agents must not edit production, test, skill, or docs files outside the allowed spec/plan files; each implementation task is performed by `implementer` and accepted by `reviewer` before commit.
- HUMAN_DECISION_REQUIRED: none.

---

## File Structure

- `.opencode/skills/daily-devlog-automation/SKILL.md` — operational OpenCode skill; update workflow step 3, add landing-date attribution guidance, update journal style/compression guidance, and add fail-closed handling for missing `origin/main` evidence.
- `docs/dev/notes/daily-devlog-automation.md` — human-facing developer note; document landing-date attribution and inline-link journal style.
- `docs/scripts/test-opencode-automation-config.mjs` — existing `node:test` policy test file; add focused assertions against `skillContent` and `notesContent`.

## Observable Acceptance Criteria

- The daily devlog skill unambiguously says `origin/main` is the source of truth for recent work.
- The skill says work belongs to the devlog date when it lands or merges into `origin/main`, regardless of original author or commit date.
- The skill gives practical inspection guidance using mainline/first-parent history, merge commits, PR merges, or equivalent landed ranges.
- The risky existing wording `Inspect recent journal entries, docs notes, plans/specs, and commits since the latest journal entry or recent day boundary.` is removed.
- The skill fails closed when `origin/main` mainline/merge evidence cannot be fetched or inspected.
- The one-paragraph journal contract explicitly permits inline Markdown links and forbids separate link lists.
- The compression/style guidance preserves important context while making prose denser.
- The developer note documents the landing-date policy and inline-link rule.
- `cd docs && node --test scripts/test-opencode-automation-config.mjs` fails before the wording updates and passes after them.
- `cd docs && npm run test:scripts` passes.
- `cd docs && npm run docs:build` passes.
- Implementation commits modify only `.opencode/skills/daily-devlog-automation/SKILL.md`, `docs/dev/notes/daily-devlog-automation.md`, and `docs/scripts/test-opencode-automation-config.mjs`.

## Validation Ladder

1. Focused tests during implementation:
   - `cd docs && node --test scripts/test-opencode-automation-config.mjs`
2. Complete relevant suite:
   - `cd docs && npm run test:scripts`
3. Broader final checks justified by docs/process risk:
   - `cd docs && npm run docs:build`
   - `git diff --check`
   - `git diff --name-only HEAD~2..HEAD | sort`
   - `git status --short`

## Out of Scope

- Do not implement a new analyzer script.
- Do not change devlog or journal index generation.
- Do not create or edit daily journal entries.
- Do not change OpenCode agents, permissions, or `.opencode/opencode.json`.
- Do not change GitHub Actions, branch protection, or repository settings.
- Do not edit runtime C++, Lua, Fennel, assets, or tests outside `docs/scripts/test-opencode-automation-config.mjs`.
- Do not create additional developer docs pages; update the existing daily devlog automation note.

---

### Task 1: Pin and Implement Landing-Date Attribution Policy

**Files:**
- Modify: `docs/scripts/test-opencode-automation-config.mjs`
- Modify: `.opencode/skills/daily-devlog-automation/SKILL.md`

**Interfaces:**
- Consumes: existing `loadFiles(): Promise<void>` helper and `skillContent: string` global in `docs/scripts/test-opencode-automation-config.mjs`.
- Produces: passing policy test named `daily devlog skill attributes work by origin/main landing date, not author date`; updated skill text that Task 2 preserves while adding style guidance.

- [ ] **Step 1: Add the failing landing-date policy test**

Add this test after the existing daily devlog skill tests in `docs/scripts/test-opencode-automation-config.mjs`:

```js
test('daily devlog skill attributes work by origin/main landing date, not author date', async () => {
    await loadFiles()

    const oneLineSkill = skillContent.replace(/\s+/g, ' ')
    const rejectsAuthorDates = /(?:author|original commit|commit\/author) dates?.{0,220}(?:must not|never|do not|not decide|not cause|skipped|backdated)|(?:must not|never|do not).{0,220}(?:author|original commit|commit\/author) dates?/i

    assert.match(oneLineSkill, /origin\/main/i,
        'SKILL.md should name origin/main as the source for recent work')
    assert.match(oneLineSkill, /source of truth/i,
        'SKILL.md should call origin/main the source of truth')
    assert.match(oneLineSkill, /mainline|first-parent/i,
        'SKILL.md should require mainline or first-parent inspection')
    assert.match(oneLineSkill, /merge commits|PR merges|landed ranges/i,
        'SKILL.md should mention merge commits, PR merges, or landed ranges')
    assert.match(oneLineSkill, /land(?:ed|ing)|merge(?:d|s)?/i,
        'SKILL.md should describe landed or merged work')
    assert.ok(rejectsAuthorDates.test(oneLineSkill),
        'SKILL.md should say author/original commit dates must not decide devlog eligibility')
    assert.doesNotMatch(skillContent,
        /Inspect recent journal entries, docs notes, plans\/specs, and commits since the latest journal entry or recent day boundary\./,
        'SKILL.md should not keep the ambiguous commits-since workflow wording')
})
```

- [ ] **Step 2: Run the focused test and verify the red state**

Run:

```bash
cd docs
node --test scripts/test-opencode-automation-config.mjs
```

Expected: FAIL in `daily devlog skill attributes work by origin/main landing date, not author date` because the current skill lacks the explicit landing-date/source-of-truth policy and still contains the ambiguous workflow step.

- [ ] **Step 3: Replace the risky workflow step**

In `.opencode/skills/daily-devlog-automation/SKILL.md`, replace workflow step 3 with:

```markdown
3. Inspect the latest relevant journal entry or recent day boundary, docs notes, plans/specs, and `origin/main` mainline/first-parent history to identify work that landed since that boundary.
```

Do not change the existing workflow numbering or surrounding branch/PR workflow steps.

- [ ] **Step 4: Add a landing-date attribution section to the skill**

Add this section after `## Workflow` and before `## Meaningful Change Filter`:

```markdown
## Landing-Date Attribution

Treat `origin/main` as the source of truth for recent work. Attribute work to the daily entry for the date it lands or merges into `origin/main`, regardless of the original author date or feature-branch commit date. Older feature-branch commits merged today are eligible for today's entry; author or original commit dates must not cause landed work to be skipped or backdated into an already-published journal entry.

Use mainline/first-parent history, merge commits, PR merges, or equivalent landed ranges on `origin/main` to decide what changed since the latest relevant journal entry or recent day boundary. Do not guess from local branch history when the `origin/main` landing evidence is unavailable.
```

- [ ] **Step 5: Update fail-closed wording for missing mainline evidence**

In `## Fail-Closed Cases`, extend the existing sentence so it includes missing `origin/main` evidence. The final sentence must include this exact clause:

```markdown
`origin/main` cannot be fetched or inspected, mainline/merge evidence is ambiguous,
```

Keep the existing fail-closed cases for dirty checkout, credentials, `gh`, validation, branch protection, required status checks, auto-merge, and unexpected files.

- [ ] **Step 6: Run the focused test and verify green state**

Run:

```bash
cd docs
node --test scripts/test-opencode-automation-config.mjs
```

Expected: PASS for the new landing-date test and all existing automation-config tests.

- [ ] **Step 7: Run focused text checks for reviewer compatibility**

Run:

```bash
rg -n "commits since the latest journal entry|origin/main|source of truth|first-parent|mainline|merge commits|PR merges|landed ranges|author date|original commit date|BLOCKED|cannot be fetched or inspected" .opencode/skills/daily-devlog-automation/SKILL.md
```

Expected:
- No match for `commits since the latest journal entry`.
- Matches for `origin/main`, `source of truth`, `first-parent` or `mainline`, `merge commits` or `PR merges` or `landed ranges`, and author/original commit date exclusion.
- Fail-closed wording mentions missing or ambiguous `origin/main` mainline/merge evidence.

- [ ] **Step 8: Request reviewer acceptance for Task 1**

Ask `reviewer` to inspect only these Task 1 files:

```text
Review Task 1 for the daily devlog landing-date plan. Confirm that docs/scripts/test-opencode-automation-config.mjs pins origin/main landing-date attribution, that .opencode/skills/daily-devlog-automation/SKILL.md removes the ambiguous commits-since wording, and that the skill fails closed when origin/main mainline/merge evidence is missing or ambiguous. Do not edit files.
```

Expected reviewer result: PASS or a bounded list of required changes. Any required change must be routed back through `implementer`, then re-reviewed.

- [ ] **Step 9: Commit Task 1**

Run:

```bash
git add docs/scripts/test-opencode-automation-config.mjs .opencode/skills/daily-devlog-automation/SKILL.md
git commit -m "docs(opencode): attribute devlogs by landing date"
```

Expected: commit succeeds with only the Task 1 files staged.

---

### Task 2: Document Inline-Link Style and Human-Facing Landing Policy

**Files:**
- Modify: `docs/scripts/test-opencode-automation-config.mjs`
- Modify: `.opencode/skills/daily-devlog-automation/SKILL.md`
- Modify: `docs/dev/notes/daily-devlog-automation.md`

**Interfaces:**
- Consumes: Task 1 landing-date skill wording and existing `notesContent: string` global loaded from `docs/dev/notes/daily-devlog-automation.md`.
- Produces:
  - passing policy test named `daily devlog skill preserves one-paragraph inline-link and compression style policy`;
  - passing policy test named `daily devlog developer note documents landing-date and inline-link policies`;
  - updated human-facing note that final validation treats as the canonical docs/dev page.

- [ ] **Step 1: Add failing style and developer-note tests**

Add these tests after the Task 1 landing-date test in `docs/scripts/test-opencode-automation-config.mjs`:

```js
test('daily devlog skill preserves one-paragraph inline-link and compression style policy', async () => {
    await loadFiles()

    const oneLineSkill = skillContent.replace(/\s+/g, ' ')

    assert.match(oneLineSkill, /single narrative paragraph|One short narrative paragraph/i,
        'SKILL.md should keep the one-paragraph journal contract')
    assert.match(oneLineSkill, /inline Markdown links/i,
        'SKILL.md should explicitly permit inline Markdown links')
    assert.match(oneLineSkill, /relevant docs, notes, plans, specs, or feature pages/i,
        'SKILL.md should limit inline links to relevant project context')
    assert.match(oneLineSkill, /forbid.{0,180}link lists/i,
        'SKILL.md should forbid separate link lists')
    assert.match(oneLineSkill, /compression\/style pass|compression pass/i,
        'SKILL.md should require a compression/style pass')
    assert.match(oneLineSkill, /denser/i,
        'SKILL.md should say compression makes prose denser')
    assert.match(oneLineSkill, /preserve.{0,160}(?:important context|main landed changes|why they matter)/i,
        'SKILL.md should say compression preserves important context')
})

test('daily devlog developer note documents landing-date and inline-link policies', async () => {
    await loadFiles()

    assert.ok(notesContent.length > 0,
        'daily devlog developer note should be present for human-facing policy')
    const oneLineNotes = notesContent.replace(/\s+/g, ' ')

    assert.match(oneLineNotes, /origin\/main/i,
        'developer note should name origin/main')
    assert.match(oneLineNotes, /land(?:ed|ing)|merge(?:d|s)?/i,
        'developer note should document landing or merge attribution')
    assert.match(oneLineNotes, /author|original commit/i,
        'developer note should say author/original commit dates do not drive attribution')
    assert.match(oneLineNotes, /inline Markdown links/i,
        'developer note should document inline Markdown links')
    assert.match(oneLineNotes, /link lists/i,
        'developer note should forbid separate link lists')
})
```

- [ ] **Step 2: Run the focused test and verify the red state**

Run:

```bash
cd docs
node --test scripts/test-opencode-automation-config.mjs
```

Expected: FAIL because the current skill does not yet mention inline Markdown links, link lists, denser compression, or preserved context, and the developer note does not yet document landing-date attribution.

- [ ] **Step 3: Update the skill journal entry contract**

In `.opencode/skills/daily-devlog-automation/SKILL.md`, replace the paragraph immediately after the journal entry shape with:

```markdown
The paragraph connects concrete work to current project goals, milestones, or recent momentum. Inline Markdown links are allowed when they point to relevant docs, notes, plans, specs, or feature pages and improve reader context. Before writing or committing, perform a compression/style pass that makes the final paragraph denser than the full report while preserving the main landed changes, why they matter, and useful inline references. Forbid section headings, bullet lists, separate link lists, commit hashes, author lists, raw file lists, and commit-summary prose.
```

- [ ] **Step 4: Add landing-date attribution to the developer note**

In `docs/dev/notes/daily-devlog-automation.md`, add this section after `## Repo-owned workflow` and before `## Safety model`:

```markdown
## Landing-date attribution

`origin/main` is the source of truth for deciding what recent work belongs in a daily entry. The automation attributes work to the date it lands or merges into `origin/main`, regardless of the original author date or feature-branch commit date. Older feature-branch commits merged today are eligible for today's entry; author or original commit dates must not cause landed work to be skipped or backdated into an already-published entry.

Agents should inspect mainline/first-parent history, merge commits, PR merges, or equivalent landed ranges on `origin/main` since the latest relevant journal entry or recent day boundary. If `origin/main` cannot be fetched or inspected, or if the mainline/merge evidence is ambiguous, the run fails closed with a BLOCKED summary instead of guessing from local branch history.
```

- [ ] **Step 5: Update the developer note safety/style paragraph**

In `## Safety model`, replace the final sentence about daily entry shape with:

```markdown
Daily entries contain only frontmatter, a date heading, and one short narrative paragraph connecting concrete landed work to current project goals or milestones. Inline Markdown links are allowed when they point to relevant docs, notes, plans, specs, or feature pages and improve reader context, but separate link lists, bullet-point summaries, section headings, commit hashes, author lists, and raw file lists are forbidden.
```

Keep the existing safety model text about credentials, `gh`, branch protection, rulesets/effective branch rules, required status checks, pull-request protection, clean checkout, and auto-merge method selection.

- [ ] **Step 6: Run the focused test and verify green state**

Run:

```bash
cd docs
node --test scripts/test-opencode-automation-config.mjs
```

Expected: PASS for all automation-config tests.

- [ ] **Step 7: Run focused text checks for the note and skill**

Run:

```bash
rg -n "inline Markdown links|separate link lists|denser|preserving the main landed changes|Landing-date attribution|origin/main|author or original commit dates|BLOCKED" .opencode/skills/daily-devlog-automation/SKILL.md docs/dev/notes/daily-devlog-automation.md
```

Expected:
- Skill matches inline link allowance, separate link list prohibition, denser compression, and preserved landed-change context.
- Developer note matches `Landing-date attribution`, `origin/main`, author/original commit date exclusion, and `BLOCKED`.

- [ ] **Step 8: Request reviewer acceptance for Task 2**

Ask `reviewer` to inspect only these Task 2 files:

```text
Review Task 2 for the daily devlog landing-date plan. Confirm that the skill journal contract permits inline Markdown links, forbids separate link lists, and makes compression denser without deleting important context. Confirm that docs/dev/notes/daily-devlog-automation.md documents origin/main landing-date attribution, author/original commit date exclusion, fail-closed behavior, and inline-link style. Do not edit files.
```

Expected reviewer result: PASS or a bounded list of required changes. Any required change must be routed back through `implementer`, then re-reviewed.

- [ ] **Step 9: Commit Task 2**

Run:

```bash
git add docs/scripts/test-opencode-automation-config.mjs .opencode/skills/daily-devlog-automation/SKILL.md docs/dev/notes/daily-devlog-automation.md
git commit -m "docs(devlog): document landing-date journal style"
```

Expected: commit succeeds with only the Task 2 files staged.

---

### Task 3: Final Validation and Scope Review

**Files:**
- Test: `docs/scripts/test-opencode-automation-config.mjs`
- Test: `.opencode/skills/daily-devlog-automation/SKILL.md`
- Test: `docs/dev/notes/daily-devlog-automation.md`

**Interfaces:**
- Consumes: committed Task 1 and Task 2 changes.
- Produces: validated implementation branch ready for final reviewer/finishing workflow; no source files are modified by this task.

- [ ] **Step 1: Run the focused policy test**

Run:

```bash
cd docs
node --test scripts/test-opencode-automation-config.mjs
```

Expected: PASS.

- [ ] **Step 2: Run the complete docs script test suite**

Run:

```bash
cd docs
npm run test:scripts
```

Expected: PASS for all `scripts/test-*.mjs` tests.

- [ ] **Step 3: Build the docs site**

Run:

```bash
cd docs
npm run docs:build
```

Expected: PASS. If the build regenerates existing docs indexes, inspect the diff and revert unrelated generated changes unless they are required by the build.

- [ ] **Step 4: Check Markdown and whitespace diff hygiene**

Run:

```bash
git diff --check
```

Expected: no trailing whitespace, conflict markers, or whitespace errors.

- [ ] **Step 5: Verify implementation commit scope**

Run:

```bash
git diff --name-only HEAD~2..HEAD | sort
```

Expected exactly:

```text
.opencode/skills/daily-devlog-automation/SKILL.md
docs/dev/notes/daily-devlog-automation.md
docs/scripts/test-opencode-automation-config.mjs
```

If additional files appear, route the cleanup through `implementer` and `reviewer` before final validation is accepted.

- [ ] **Step 6: Verify no uncommitted changes remain**

Run:

```bash
git status --short
```

Expected: no output.

- [ ] **Step 7: Request final reviewer acceptance**

Ask `reviewer` to perform final acceptance:

```text
Perform final review for the daily devlog landing-date implementation. Confirm all observable acceptance criteria in docs/plans/2026-08-01-daily-devlog-landing-date.md, confirm the validation commands passed, confirm only the expected three implementation files changed in the last two commits, and confirm OpenCode restart guidance remains documented. Do not edit files.
```

Expected reviewer result: PASS. If reviewer reports a defect, route the fix through `implementer`, rerun the focused test, rerun the complete docs script suite, rerun docs build, and request reviewer acceptance again.
