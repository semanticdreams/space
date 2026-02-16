import { cp, lstat, mkdir, unlink } from 'node:fs/promises'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const __dirname = dirname(fileURLToPath(import.meta.url))
const docsDir = resolve(__dirname, '..')
const source = resolve(docsDir, '../assets/pics/space.png')
const target = resolve(docsDir, 'public/space.png')

await mkdir(dirname(target), { recursive: true })

try {
    const stats = await lstat(target)
    if (stats.isSymbolicLink()) {
        await unlink(target)
    }
}
catch (error) {
    if (error.code !== 'ENOENT') {
        throw error
    }
}

await cp(source, target)
