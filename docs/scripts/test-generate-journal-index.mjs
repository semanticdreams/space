import assert from 'node:assert/strict'
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import test from 'node:test'

import { format_journal_index, generate_journal_index } from './generate-journal-index.mjs'

test('format_journal_index renders dated entries newest first', () => {
    assert.equal(format_journal_index([
        '2025-09-16.md',
        'index.md',
        'notes.md',
        '2026-07-14.md',
        '2026-02-08.md',
        '2026-07-14.md'
    ]), `---
type: index
aliases:
  - Journal
tags:
  - index
  - journal
---

# Journal

Chronological log of development work and decisions. Each entry records what was built, problems encountered, and ideas surfaced on a given day.

- [2026-07-14](./2026-07-14)
- [2026-02-08](./2026-02-08)
- [2025-09-16](./2025-09-16)
`)
})

test('generate_journal_index writes the rendered index', async () => {
    const root = await mkdtemp(join(tmpdir(), 'space-journal-index-'))
    const journalDir = join(root, 'journal')
    const indexPath = join(journalDir, 'index.md')

    await mkdir(journalDir, { recursive: true })
    await writeFile(join(journalDir, '2026-01-01.md'), '# 2026-01-01\n')
    await writeFile(join(journalDir, '2026-01-03.md'), '# 2026-01-03\n')
    await writeFile(join(journalDir, 'draft.md'), '# Draft\n')
    await writeFile(indexPath, 'old index\n')

    const rendered = await generate_journal_index({ journalDir, indexPath })

    assert.equal(await readFile(indexPath, 'utf8'), rendered)
    assert.match(rendered, /- \[2026-01-03\]\(\.\/2026-01-03\)\n- \[2026-01-01\]\(\.\/2026-01-01\)/)
    assert.doesNotMatch(rendered, /draft/)

    await rm(root, { recursive: true, force: true })
})
