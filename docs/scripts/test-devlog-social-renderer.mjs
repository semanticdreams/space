import test from 'node:test'
import assert from 'node:assert/strict'

import { format_social_body, format_social_message, social_renderer_test_exports } from './devlog-social-renderer.mjs'

const { render_inline_text } = social_renderer_test_exports()

function create_entry(body)
{
    return {
        id: '2025-09-16',
        title: '2025-09-16',
        body,
        urlPath: '/dev/devlog#_2025-09-16'
    }
}

test('drops markdown image syntax from social output', () => {
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
            '- link: https://spaceui.org/dev/devlog/doc.md',
        ].join('\n')
    )
})

test('formats the full social message with public entry anchor URL', () => {
    const entry = create_entry('Hello world')
    assert.equal(
        format_social_message(entry, 'https://spaceui.org/'),
        'Devlog 2025-09-16\nHello world\n\nhttps://spaceui.org/dev/devlog#_2025-09-16'
    )
})

test('keeps inline code spans intact while rendering links around them', () => {
    const entry = create_entry('See `[x](y)` and [docs](./docs.md)')
    assert.equal(
        render_inline_text(entry.body, entry, 'https://spaceui.org'),
        'See `[x](y)` and docs: https://spaceui.org/dev/devlog/docs.md'
    )
})
