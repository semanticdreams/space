import { readdir, readFile, writeFile } from 'node:fs/promises'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const __dirname = dirname(fileURLToPath(import.meta.url))
const docsDir = resolve(__dirname, '..')
const devlogDir = resolve(docsDir, 'dev', 'journal')
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

    let startIndex = 0
    let frontmatterEnd = 0
    if (lines[0]?.trim() === '---') {
        startIndex = 1
        while (startIndex < lines.length && lines[startIndex].trim() !== '---') {
            startIndex += 1
        }
        frontmatterEnd = startIndex
        startIndex += 1
        while (startIndex < lines.length && lines[startIndex].trim() === '') {
            startIndex += 1
        }
    }

    const hasDevlogTag = lines.slice(1, frontmatterEnd).some((line) => line.includes('devlog'))
    if (!hasDevlogTag) {
        continue
    }

    if (startIndex >= lines.length || !lines[startIndex]?.startsWith('# ')) {
        throw new Error(`Expected heading "# " in ${entryName}`)
    }

    const title = lines[startIndex].slice(2).trim()
    const body = lines
        .slice(startIndex + 1)
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
