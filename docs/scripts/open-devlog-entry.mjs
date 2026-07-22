import { access, mkdir, writeFile } from 'node:fs/promises'
import { constants as fsConstants } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { spawn } from 'node:child_process'

const __dirname = dirname(fileURLToPath(import.meta.url))
const docsDir = resolve(__dirname, '..')
const devlogDir = resolve(docsDir, 'dev', 'journal')

function format_today_utc()
{
    const now = new Date()
    const year = String(now.getUTCFullYear())
    const month = String(now.getUTCMonth() + 1).padStart(2, '0')
    const day = String(now.getUTCDate()).padStart(2, '0')
    return `${year}-${month}-${day}`
}

async function exists(path)
{
    try {
        await access(path, fsConstants.F_OK)
        return true
    }
    catch {
        return false
    }
}

async function ensure_entry(entryPath, date)
{
    if (await exists(entryPath)) {
        return
    }

    await mkdir(dirname(entryPath), { recursive: true })
    await writeFile(entryPath, `---\ntype: journal\ntags: [journal, devlog]\ncreated: ${date}\n---\n\n# ${date}\n\n`, 'utf8')
}

async function command_exists(command)
{
    const checker = process.platform === 'win32' ? 'where' : 'command'
    const args = process.platform === 'win32' ? [command] : ['-v', command]

    return await new Promise((resolvePromise) => {
        const child = spawn(checker, args, { stdio: 'ignore', shell: false })
        child.on('exit', (code) => resolvePromise(code === 0))
        child.on('error', () => resolvePromise(false))
    })
}

function split_command(command)
{
    const parts = command.match(/(?:[^\s"]+|"[^"]*")+/g)
    if (!parts || parts.length === 0) {
        throw new Error('Editor command is empty')
    }

    return parts.map((part) => part.replace(/^"(.*)"$/, '$1'))
}

async function open_entry(entryPath)
{
    const preferredEditor = process.env.SPACE_EDITOR || process.env.VISUAL || process.env.EDITOR

    if (process.env.SPACE_DEVLOG_NO_OPEN === '1') {
        console.log(entryPath)
        return
    }

    if (preferredEditor) {
        const [command, ...args] = split_command(preferredEditor)
        await run_command(command, [...args, entryPath])
        return
    }

    if (process.platform === 'darwin') {
        await run_command('open', [entryPath])
        return
    }

    if (process.platform === 'win32') {
        await run_command('cmd', ['/c', 'start', '', entryPath])
        return
    }

    if (await command_exists('xdg-open')) {
        await run_command('xdg-open', [entryPath])
        return
    }

    throw new Error('No editor configured. Set SPACE_EDITOR, VISUAL, or EDITOR.')
}

async function run_command(command, args)
{
    await new Promise((resolvePromise, rejectPromise) => {
        const child = spawn(command, args, { stdio: 'inherit', shell: false })
        child.on('exit', (code) => {
            if (code === 0) {
                resolvePromise()
                return
            }

            rejectPromise(new Error(`${command} exited with code ${code}`))
        })
        child.on('error', rejectPromise)
    })
}

const date = format_today_utc()
const entryPath = join(devlogDir, `${date}.md`)

await ensure_entry(entryPath, date)
await open_entry(entryPath)
