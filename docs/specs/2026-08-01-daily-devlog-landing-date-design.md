# Daily Devlog Landing-Date Attribution Design

## Purpose

The daily devlog automation must describe work on the day it becomes part of `origin/main`, not on the day a feature-branch commit was authored. Feature branches may contain commits from earlier dates; if the automation filters by commit/author date, that work can miss every daily entry. The workflow should instead treat `origin/main` as the source of truth and attribute meaningful changes to the date they land through a merge or direct mainline integration.

## Direction

Update the repo-owned `daily-devlog-automation` skill, its developer note, and the existing automation-config tests. The skill should explicitly instruct agents to inspect `origin/main` mainline or first-parent history for changes that landed since the latest devlog entry or recent day boundary. The test should pin that policy so future edits cannot silently return to ambiguous “commits since” wording.

This remains a documentation-and-process correction rather than a new analyzer script. The automation is still agent-operated, but its operating contract becomes specific enough to avoid using raw commit dates as the deciding calendar.

## Components

- `.opencode/skills/daily-devlog-automation/SKILL.md` should define landing-date attribution: work belongs to the devlog date when it appears on `origin/main`, regardless of original author/commit date.
- `docs/dev/notes/daily-devlog-automation.md` should explain the same policy for humans configuring or auditing the automation.
- `docs/scripts/test-opencode-automation-config.mjs` should assert that the skill mentions `origin/main` landing/merge attribution and rejects author-date-driven interpretation.
- Existing devlog index generation remains unchanged.

## Data Flow

1. The scheduled automation fetches `origin/main`.
2. It identifies the latest relevant devlog/journal boundary.
3. It inspects `origin/main` mainline/first-parent history, merge commits, PR merges, or equivalent landed ranges to determine what changed since that boundary.
4. It applies the meaningful-change filter to the landed work.
5. If warranted, the implementer writes one devlog paragraph for the current automation date.

The key invariant is that older feature-branch commits merged today are eligible for today’s entry. Their author dates must not cause them to be skipped or backdated into an already-published journal entry.

## Journal Style Update

The entry stays a single narrative paragraph with the existing frontmatter and date heading. Inline Markdown links are allowed when they point to relevant docs, notes, plans, specs, or feature pages and improve reader context. Link lists, bullet lists, headings, raw file lists, commit hashes, author lists, and commit-summary prose remain forbidden.

The compression pass should make the final paragraph denser than the full report without deleting important context. It should preserve the main landed changes, why they matter, and useful inline references instead of reducing the entry to a generic one-sentence summary.

## Error Handling and Safety

If `origin/main` cannot be fetched or inspected, the automation should fail closed rather than guessing from local branch history or commit dates. If the evidence is ambiguous, the run should leave a BLOCKED summary identifying the missing mainline/merge information.

## Testing

Add a focused assertion to `docs/scripts/test-opencode-automation-config.mjs` alongside the existing skill-policy tests. The test should read `.opencode/skills/daily-devlog-automation/SKILL.md` and require wording that covers all of these ideas:

- `origin/main` is the source of truth for recent work;
- work is attributed by landing/merge date on `origin/main`;
- author or original commit date must not decide whether work appears in a daily entry.

Existing docs-script tests and docs build validation remain the relevant runtime checks.

## Acceptance Criteria

- The daily devlog skill unambiguously says to decide “what happened” by when work lands in `origin/main`, not by original commit/author date.
- The skill gives practical inspection guidance using mainline/first-parent history, merge commits, PR merges, or equivalent landed ranges.
- The one-paragraph contract explicitly permits inline Markdown links and forbids separate link lists.
- The compression/style guidance preserves important context while making the prose denser.
- The developer note documents the landing-date policy and inline-link rule.
- The automation-config test suite fails if the skill loses the landing-date attribution requirement.
