import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

import {
    collect_entry_images,
    collect_entry_image_urls,
    format_discord_message,
    format_matrix_message,
    format_social_body,
    render_inline_text
} from './devlog-social-renderer.mjs'

const __dirname = dirname(fileURLToPath(import.meta.url))
const docsDir = join(__dirname, '..')

function create_entry(body)
{
    return {
        id: '2025-09-16',
        title: '2025-09-16',
        body,
        urlPath: '/dev/devlog#_2025-09-16'
    }
}

async function read_fixture_entry(id)
{
    const raw = await readFile(join(docsDir, 'dev', 'devlog', id + '.md'), 'utf8')
    const normalized = raw.replace(/\r\n/g, '\n')
    const lines = normalized.split('\n')

    return {
        id,
        title: lines[0].slice(2).trim(),
        body: lines.slice(1).join('\n').trim(),
        urlPath: '/dev/devlog#_' + id
    }
}

test('drops markdown image syntax from social body output', () => {
    const entry = create_entry('![Space Prototype Screenshot](../space-prototype-screenshot1.png)')
    assert.equal(
        format_social_body(entry, 'https://spaceui.org'),
        ''
    )
})

test('renders markdown links as visible labels plus absolute URLs', () => {
    const entry = create_entry('[notes](./notes.md) and [site](https://example.com)')
    assert.equal(
        format_social_body(entry, 'https://spaceui.org'),
        'notes: https://spaceui.org/dev/devlog/notes.md and site: https://example.com'
    )
})

test('preserves fenced code blocks', () => {
    const entry = create_entry('```lua\n(print :ok)\n```')
    assert.equal(
        format_social_body(entry, 'https://spaceui.org'),
        '```lua\n(print :ok)\n```'
    )
})

test('renders simple lists and blockquotes without losing URLs', () => {
    const entry = create_entry([
        '- first item',
        '- [link](./doc.md)',
        '',
        '> ![Shot](../img.png)'
    ].join('\n'))

    assert.equal(
        format_social_body(entry, 'https://spaceui.org'),
        [
            '- first item',
            '- link: https://spaceui.org/dev/devlog/doc.md'
        ].join('\n')
    )
})

test('keeps inline code spans intact while rendering links around them', () => {
    const entry = create_entry('See `[x](y)` and [docs](./docs.md)')
    assert.equal(
        render_inline_text(entry.body, entry, 'https://spaceui.org'),
        'See `[x](y)` and docs: https://spaceui.org/dev/devlog/docs.md'
    )
})

test('discord message wraps final entry url and emits image embeds', async () => {
    const entry = await read_fixture_entry('2025-09-16')
    const message = format_discord_message(entry, 'https://spaceui.org/')

    assert.match(message.content, /^Devlog 2025-09-16\n\n/)
    assert.match(message.content, /<https:\/\/spaceui\.org\/dev\/devlog#_2025-09-16>$/)
    assert.deepEqual(message.embeds, [
        {
            image: {
                url: 'https://spaceui.org/dev/space-prototype-screenshot1.png'
            }
        }
    ])
})

test('matrix message keeps plain final entry url and no embed payload', async () => {
    const entry = await read_fixture_entry('2025-09-16')
    const message = format_matrix_message(entry, 'https://spaceui.org/')

    assert.equal(message.msgtype, 'm.text')
    assert.match(message.body, /^Devlog 2025-09-16\n\n/)
    assert.match(message.body, /\n\nhttps:\/\/spaceui\.org\/dev\/devlog#_2025-09-16$/)
})

test('collects image metadata from a complete fixture entry', async () => {
    const entry = await read_fixture_entry('2025-09-16')
    assert.deepEqual(
        collect_entry_images(entry, 'https://spaceui.org'),
        [{
            alt: 'Space Prototype Screenshot',
            target: '../space-prototype-screenshot1.png',
            url: 'https://spaceui.org/dev/space-prototype-screenshot1.png'
        }]
    )
    assert.deepEqual(
        collect_entry_image_urls(entry, 'https://spaceui.org'),
        ['https://spaceui.org/dev/space-prototype-screenshot1.png']
    )
})

test('renders a complete text-only fixture entry cleanly', async () => {
    const entry = await read_fixture_entry('2025-09-24')
    const body = format_social_body(entry, 'https://spaceui.org')

    assert.match(body, /Changed to load classes in Python prototype directly from z folder/)
    assert.match(body, /Fixed fbo update issue by updating Lua's fbo handle on viewport change\./)
    assert.equal(collect_entry_image_urls(entry, 'https://spaceui.org').length, 0)
})
