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

async function loadFiles() {
    if (skillContent) return
    skillContent = await readFile(join(repoRoot, '.opencode', 'skills', 'daily-devlog-automation', 'SKILL.md'), 'utf8')
    supervisorContent = await readFile(join(repoRoot, '.opencode', 'agents', 'supervisor.md'), 'utf8')
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
