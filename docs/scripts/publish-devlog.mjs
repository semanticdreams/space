import { mkdir, readFile, writeFile } from 'node:fs/promises'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import crypto from 'node:crypto'

const __dirname = dirname(fileURLToPath(import.meta.url))
const docsDir = resolve(__dirname, '..')
const devlogDir = join(docsDir, 'dev', 'devlog')

function get_required_env(name)
{
    const value = process.env[name]
    if (!value) {
        throw new Error(`${name} is required`)
    }

    return value
}

function normalize_base_url(url)
{
    return url.replace(/\/+$/, '')
}

function less_than_entry_id(entryId, maxExclusive)
{
    return !maxExclusive || entryId < maxExclusive
}

async function read_state(statePath)
{
    try {
        const raw = await readFile(statePath, 'utf8')
        const state = JSON.parse(raw)
        if (!state.entries || typeof state.entries !== 'object') {
            return { entries: {} }
        }

        return state
    }
    catch (error) {
        if (error.code === 'ENOENT') {
            return { entries: {} }
        }

        throw error
    }
}

async function write_state(statePath, state)
{
    await mkdir(dirname(statePath), { recursive: true })
    await writeFile(statePath, `${JSON.stringify(state, null, 2)}\n`, 'utf8')
}

async function read_entries()
{
    const { readdir } = await import('node:fs/promises')
    const names = (await readdir(devlogDir))
        .filter((name) => name.endsWith('.md'))
        .sort()

    const entries = []

    for (const name of names) {
        const id = name.replace(/\.md$/, '')
        const path = join(devlogDir, name)
        const raw = await readFile(path, 'utf8')
        const normalized = raw.replace(/\r\n/g, '\n')
        const lines = normalized.split('\n')

        if (!lines[0]?.startsWith('# ')) {
            throw new Error(`Expected first line of ${name} to start with "# "`)
        }

        const body = lines.slice(1).join('\n').trim()
        entries.push({
            id,
            title: lines[0].slice(2).trim(),
            body,
            urlPath: `/dev/devlog/${id}`
        })
    }

    return entries
}

function ensure_entry_state(state, entryId)
{
    if (!state.entries[entryId]) {
        state.entries[entryId] = {}
    }

    return state.entries[entryId]
}

function is_sent(state, entryId, channel)
{
    return state.entries[entryId]?.[channel]?.status === 'sent'
}

function format_plaintext_message(entry, baseUrl)
{
    return `Devlog ${entry.id}\n${entry.body}\n\n${baseUrl}${entry.urlPath}`
}

async function post_discord(entry, baseUrl)
{
    const webhookUrl = process.env.DISCORD_WEBHOOK_URL
    if (!webhookUrl) {
        return { skipped: true, reason: 'DISCORD_WEBHOOK_URL not set' }
    }

    const response = await fetch(webhookUrl, {
        method: 'POST',
        headers: {
            'content-type': 'application/json'
        },
        body: JSON.stringify({
            content: format_plaintext_message(entry, baseUrl)
        })
    })

    if (!response.ok) {
        throw new Error(`Discord webhook failed with ${response.status} ${response.statusText}`)
    }

    return { skipped: false }
}

async function post_matrix(entry, baseUrl)
{
    const homeserver = process.env.MATRIX_HOMESERVER
    const accessToken = process.env.MATRIX_ACCESS_TOKEN
    const roomId = process.env.MATRIX_ROOM_ID

    if (!homeserver || !accessToken || !roomId) {
        return { skipped: true, reason: 'Matrix publish env vars not fully set' }
    }

    const txnId = crypto.randomUUID()
    const endpoint = `${homeserver.replace(/\/+$/, '')}/_matrix/client/v3/rooms/${encodeURIComponent(roomId)}/send/m.room.message/${txnId}`
    const response = await fetch(endpoint, {
        method: 'PUT',
        headers: {
            authorization: `Bearer ${accessToken}`,
            'content-type': 'application/json'
        },
        body: JSON.stringify({
            msgtype: 'm.text',
            body: format_plaintext_message(entry, baseUrl)
        })
    })

    if (!response.ok) {
        throw new Error(`Matrix send failed with ${response.status} ${response.statusText}`)
    }

    return { skipped: false }
}

function configured_channels()
{
    const channels = []

    if (process.env.DISCORD_WEBHOOK_URL) {
        channels.push('discord')
    }

    if (process.env.MATRIX_HOMESERVER && process.env.MATRIX_ACCESS_TOKEN && process.env.MATRIX_ROOM_ID) {
        channels.push('matrix')
    }

    return channels
}

function seed_existing_entries(state, entries, baseUrl, channels, seedBeforeExclusive)
{
    const sentAt = new Date().toISOString()
    let seededCount = 0

    for (const entry of entries) {
        if (!entry.body || !less_than_entry_id(entry.id, seedBeforeExclusive)) {
            continue
        }

        const entryState = ensure_entry_state(state, entry.id)
        for (const channel of channels) {
            entryState[channel] = {
                status: 'sent',
                sent_at: sentAt,
                seeded: true,
                url: `${baseUrl}${entry.urlPath}`
            }
        }

        seededCount += 1
    }

    return seededCount
}

async function publish_channel(channel, entry, state, baseUrl)
{
    if (is_sent(state, entry.id, channel)) {
        return { channel, skipped: true, reason: 'already sent' }
    }

    const result = channel === 'discord'
        ? await post_discord(entry, baseUrl)
        : await post_matrix(entry, baseUrl)

    if (result.skipped) {
        return { channel, skipped: true, reason: result.reason }
    }

    const entryState = ensure_entry_state(state, entry.id)
    entryState[channel] = {
        status: 'sent',
        sent_at: new Date().toISOString(),
        url: `${baseUrl}${entry.urlPath}`
    }

    return { channel, skipped: false }
}

const statePath = get_required_env('DEVLOG_STATE_PATH')
const baseUrl = normalize_base_url(get_required_env('DEVLOG_BASE_URL'))
const state = await read_state(statePath)
const entries = await read_entries()
const channels = configured_channels()
const seedOnEmptyState = process.env.DEVLOG_SEED_ON_EMPTY_STATE === '1'
const maxEntryIdExclusive = process.env.DEVLOG_MAX_ENTRY_ID_EXCLUSIVE
const seedBeforeEntryIdExclusive = process.env.DEVLOG_SEED_BEFORE_ENTRY_ID_EXCLUSIVE
let hadError = false

if (seedOnEmptyState && Object.keys(state.entries).length === 0 && channels.length > 0) {
    const seededCount = seed_existing_entries(state, entries, baseUrl, channels, seedBeforeEntryIdExclusive)
    await write_state(statePath, state)
    console.log(`Seeded publish state for ${seededCount} entries across ${channels.length} channel(s)`)
}

for (const entry of entries) {
    if (!entry.body) {
        console.log(`Skipping ${entry.id}: empty body`)
        continue
    }

    if (!less_than_entry_id(entry.id, maxEntryIdExclusive)) {
        console.log(`Skipping ${entry.id}: not yet publishable`)
        continue
    }

    for (const channel of channels) {
        try {
            const result = await publish_channel(channel, entry, state, baseUrl)
            if (result.skipped) {
                console.log(`Skipping ${entry.id} for ${channel}: ${result.reason}`)
            }
            else {
                console.log(`Published ${entry.id} to ${channel}`)
            }
        }
        catch (error) {
            hadError = true
            console.error(`Failed to publish ${entry.id} to ${channel}: ${error.message}`)
        }
    }
}

await write_state(statePath, state)

if (hadError) {
    process.exitCode = 1
}
