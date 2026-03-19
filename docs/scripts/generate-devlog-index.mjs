import { readdir, readFile, writeFile } from 'node:fs/promises'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const __dirname = dirname(fileURLToPath(import.meta.url))
const docsDir = resolve(__dirname, '..')
const devlogDir = join(docsDir, 'dev', 'devlog')
const indexPath = join(docsDir, 'dev', 'devlog.md')

const entryNames = (await readdir(devlogDir))
    .filter((name) => name.endsWith('.md'))
    .sort()
    .reverse()

const sections = []

for (const entryName of entryNames) {
    const entryPath = join(devlogDir, entryName)
    const raw = await readFile(entryPath, 'utf8')
    const lines = raw.replace(/\r\n/g, '\n').split('\n')

    if (!lines[0]?.startsWith('# ')) {
        throw new Error(`Expected first line of ${entryName} to start with "# "`)
    }

    const title = lines[0].slice(2).trim()
    const body = lines
        .slice(1)
        .join('\n')
        .replace(/^\n+/, '')
        .replace(/\]\((?![a-z]+:|\/|#)([^)]+)\)/gi, (_, target) => {
            if (target.startsWith('../')) {
                return `](./${target.slice(3)})`
            }

            return `](${target})`
        })
        .trimEnd()

    if (!body) {
        continue
    }

    sections.push(`## ${title}\n${body}`)
}

const output = `# Devlog

${sections.join('\n\n')}
`

await writeFile(indexPath, output)
