import { mkdir, readdir, writeFile } from 'node:fs/promises'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

const __dirname = dirname(fileURLToPath(import.meta.url))
const docsDir = resolve(__dirname, '..')
const defaultJournalDir = resolve(docsDir, 'dev', 'journal')
const defaultIndexPath = join(defaultJournalDir, 'index.md')

const datedEntryPattern = /^\d{4}-\d{2}-\d{2}\.md$/

export function format_journal_index(entryNames)
{
    const entries = [...new Set(entryNames)]
        .filter((name) => datedEntryPattern.test(name))
        .sort()
        .reverse()
        .map((name) => name.slice(0, -3))

    const links = entries.map((date) => `- [${date}](./${date})`).join('\n')

    return `---
type: index
aliases:
  - Journal
tags:
  - index
  - journal
---

# Journal

Chronological log of development work and decisions. Each entry records what was built, problems encountered, and ideas surfaced on a given day.

${links}
`
}

export async function generate_journal_index(options = {})
{
    const journalDir = options.journalDir ?? defaultJournalDir
    const indexPath = options.indexPath ?? defaultIndexPath
    const entryNames = await readdir(journalDir)
    const output = format_journal_index(entryNames)

    await mkdir(dirname(indexPath), { recursive: true })
    await writeFile(indexPath, output, 'utf8')
    return output
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
    await generate_journal_index()
}
