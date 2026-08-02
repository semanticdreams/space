import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const __dirname = dirname(fileURLToPath(import.meta.url))
const repoRoot = join(__dirname, '..', '..')

let skillContent = ''
let supervisorContent = ''
let notesContent = ''
let workflowDebugContent = ''

async function loadFiles() {
    if (skillContent) return
    skillContent = await readFile(join(repoRoot, '.opencode', 'skills', 'daily-devlog-automation', 'SKILL.md'), 'utf8')
    supervisorContent = await readFile(join(repoRoot, '.opencode', 'agents', 'supervisor.md'), 'utf8')
    workflowDebugContent = await readFile(join(repoRoot, '.opencode', 'skills', 'github-workflow-debug', 'SKILL.md'), 'utf8')
    try {
        notesContent = await readFile(join(repoRoot, 'docs', 'dev', 'notes', 'daily-devlog-automation.md'), 'utf8')
    } catch { /* optional */ }
}

test('daily devlog skill mentions GitHub rulesets or effective branch rules, not only classic protection', async () => {
    await loadFiles()
    const hasRulesets = skillContent.includes('ruleset') ||
        skillContent.includes('rules/branches') ||
        skillContent.includes('effective branch rule') ||
        skillContent.includes('effective rules')
    assert.ok(hasRulesets,
        'SKILL.md should mention rulesets or effective branch rules, not only classic protection')
})

test('daily devlog skill includes effective branch rules command', async () => {
    await loadFiles()
    const hasCommand = skillContent.includes('rules/branches/main') ||
        skillContent.includes('rules/branches/<branch>')
    assert.ok(hasCommand,
        'SKILL.md should include gh api repos/<owner>/<repo>/rules/branches/main or equivalent')
})

test('daily devlog skill requires verifying required status checks before auto-merge', async () => {
    await loadFiles()
    assert.ok(
        // Must mention required status checks in context of verification/auto-merge
        /required.status.check/i.test(skillContent),
        'SKILL.md should require verifying required status checks before auto-merge'
    )
})

test('daily devlog skill requires verifying pull-request protection before auto-merge', async () => {
    await loadFiles()
    // Must mention pull-request rules / PR protection in context of verification
    const hasPrProtection = /pull.request.*(?:protect|rule|required|verified)|pull.request/i.test(skillContent) &&
        /auto.merge/i.test(skillContent)
    assert.ok(hasPrProtection,
        'SKILL.md should require verifying pull-request protection before auto-merge')
})

test('daily devlog skill does not hard-code --squash and instead selects merge method from rules', async () => {
    await loadFiles()
    // The skill must NOT require --squash as the only option
    const hasHardcodedSquash = /gh pr merge --auto --squash automation\/daily-devlog/.test(skillContent)
    // The skill must mention using the merge method from verified rules
    const hasMergeMethodFromRules = /merge.method/i.test(skillContent) ||
        /allowed.merge/i.test(skillContent) ||
        /--merge automation\/daily-devlog/.test(skillContent) ||
        /merge.*allowed/i.test(skillContent)
    assert.ok(!hasHardcodedSquash,
        'SKILL.md must NOT hard-code --squash for daily auto-merge')
    assert.ok(hasMergeMethodFromRules,
        'SKILL.md should say to use the merge method allowed by verified branch rules')
})

test('supervisor permissions allow rules/branches/main API', async () => {
    await loadFiles()
    const hasAllow = supervisorContent.includes('gh api repos/*/*/rules/branches/main')
    assert.ok(hasAllow,
        'supervisor.md must allow gh api repos/*/*/rules/branches/main*')
})

test('supervisor permissions allow --merge for daily auto-merge', async () => {
    await loadFiles()
    const hasMergeAllow = /gh pr merge --auto --merge automation\/daily-devlog\/\?\?\?\?-\?\?-\?\?/.test(supervisorContent)
    assert.ok(hasMergeAllow,
        'supervisor.md must allow gh pr merge --auto --merge automation/daily-devlog/????-??-??')
})

test('supervisor permissions keep existing --squash daily allow alongside new --merge allow', async () => {
    await loadFiles()
    const hasSquashAllow = /gh pr merge --auto --squash automation\/daily-devlog\/\?\?\?\?-\?\?-\?\?/.test(supervisorContent)
    assert.ok(hasSquashAllow,
        'supervisor.md should retain the existing --squash daily allow for transitional safety')
})

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
    assert.match(oneLineSkill, /preserv.{0,160}(?:important context|main landed changes|why they matter)/i,
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

test('github workflow debug lands through a PR branch instead of local main', async () => {
    await loadFiles()

    const oneLineSkill = workflowDebugContent.replace(/\s+/g, ' ')

    assert.match(oneLineSkill, /final PR branch/i,
        'workflow-debug skill should name a final PR branch')
    assert.match(oneLineSkill, /origin\/main/i,
        'workflow-debug final PR branch should be created from origin/main')
    assert.match(oneLineSkill, /squash-merge/i,
        'workflow-debug skill should keep squash-merge landing semantics')
    assert.match(oneLineSkill, /remove.{0,160}temporary.{0,80}trigger/i,
        'workflow-debug skill should remove the temporary workflow trigger before final commit')
    assert.match(oneLineSkill, /staged review/i,
        'workflow-debug skill should require staged review')
    assert.match(oneLineSkill, /gh pr create --base main --head <final-pr-branch> --fill/i,
        'workflow-debug skill should create a PR with gh pr create')
    assert.match(oneLineSkill, /PR URL/i,
        'workflow-debug skill should return the PR URL')
    assert.match(oneLineSkill, /branch-protection incompatible/i,
        'workflow-debug skill should say direct main push is branch-protection incompatible')

    assert.doesNotMatch(workflowDebugContent, /## Final landing on main/,
        'workflow-debug skill must not title the landing path as local main')
    assert.doesNotMatch(oneLineSkill, /Check out `main`|Fast-forward `main`|Final commit on main|Ready to push|git checkout main|checkout main|check out main|commit (?:on|to|onto) (?:`?main`?|main)|squash[- ]merge\s+(?:onto|into)\s+(?:`?main`?|main)|squash\s+(?:onto|into)\s+(?:`?main`?|main)/i,
        'workflow-debug skill must not reference local main checkout, commit-on-main, or ready-to-push-main output')
    assert.doesNotMatch(workflowDebugContent, /git push origin main/,
        'workflow-debug skill must not tell agents to push main directly')
})

test('supervisor permissions allow workflow-debug final PR branch integration only', async () => {
    await loadFiles()

    assert.ok(supervisorContent.includes('"git push origin HEAD:refs/heads/opencode/workflow-debug-pr/*": allow'),
        'supervisor should allow pushing workflow-debug final PR branches')
    assert.ok(supervisorContent.includes('"gh pr create --base main --head opencode/workflow-debug-pr/* --fill": allow'),
        'supervisor should allow creating workflow-debug final PRs')
    assert.ok(supervisorContent.includes('"git push origin main": ask'),
        'direct main push must remain ask-gated, not allowed')
    assert.ok(!supervisorContent.includes('"git push origin main": allow'),
        'direct main push must not be allowed')
})
