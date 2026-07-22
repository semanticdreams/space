import { mkdir, readFile, stat, writeFile } from 'node:fs/promises'
import { basename, dirname, extname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import crypto from 'node:crypto'
import {
    collect_entry_images,
    format_discord_message,
    format_matrix_message
} from './devlog-social-renderer.mjs'

const __dirname = dirname(fileURLToPath(import.meta.url))
const docsDir = resolve(__dirname, '..')
const devlogDir = resolve(docsDir, '..', 'knowledge', 'journal')

function get_required_env(name)
{
    const value = process.env[name]
    if (!value) {
        throw new Error(name + ' is required')
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

function infer_mime_type(path)
{
    const extension = extname(path).toLowerCase()

    if (extension === '.png') {
        return 'image/png'
    }
    if (extension === '.jpg' || extension === '.jpeg') {
        return 'image/jpeg'
    }
    if (extension === '.gif') {
        return 'image/gif'
    }
    if (extension === '.webp') {
        return 'image/webp'
    }
    if (extension === '.avif') {
        return 'image/avif'
    }
    if (extension === '.svg') {
        return 'image/svg+xml'
    }

    return 'application/octet-stream'
}

function matrix_api_base(homeserver)
{
    return homeserver.replace(/\/+$/, '')
}

function matrix_txn_id()
{
    return crypto.randomUUID()
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
    await writeFile(statePath, JSON.stringify(state, null, 2) + '\n', 'utf8')
}

async function read_entries()
{
    const fsPromises = await import('node:fs/promises')
    const names = (await fsPromises.readdir(devlogDir))
        .filter((name) => name.endsWith('.md'))
        .sort()

    const entries = []

    for (const name of names) {
        const id = name.replace(/\.md$/, '')
        const path = join(devlogDir, name)
        const raw = await readFile(path, 'utf8')
        const normalized = raw.replace(/\r\n/g, '\n')
        const lines = normalized.split('\n')

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
            throw new Error('Expected heading "# " in ' + name)
        }

        const body = lines.slice(startIndex + 1).join('\n').trim()
        entries.push({
            id,
            title: lines[startIndex].slice(2).trim(),
            body,
            sourcePath: path,
            urlPath: '/dev/devlog#_' + id
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
    const channelState = state.entries[entryId] && state.entries[entryId][channel]
    return channelState && channelState.status === 'sent' && channelState.seeded !== true
}

function ensure_channel_state(state, entryId, channel)
{
    const entryState = ensure_entry_state(state, entryId)
    if (!entryState[channel]) {
        entryState[channel] = {}
    }

    return entryState[channel]
}

async function post_discord(entry, baseUrl)
{
    const webhookUrl = process.env.DISCORD_WEBHOOK_URL
    if (!webhookUrl) {
        return { skipped: true, reason: 'DISCORD_WEBHOOK_URL not set' }
    }

    const message = format_discord_message(entry, baseUrl)
    const response = await fetch(webhookUrl, {
        method: 'POST',
        headers: {
            'content-type': 'application/json'
        },
        body: JSON.stringify({
            content: message.content,
            embeds: message.embeds
        })
    })

    if (!response.ok) {
        throw new Error('Discord webhook failed with ' + response.status + ' ' + response.statusText)
    }

    return { skipped: false }
}

function resolve_entry_image_file(entry, target)
{
    if (/^[a-z]+:/i.test(target)) {
        throw new Error('Matrix image publishing does not support remote image target: ' + target)
    }

    if (target.startsWith('/')) {
        return resolve(docsDir, '.' + target)
    }

    return resolve(dirname(entry.sourcePath), target)
}

async function upload_matrix_media(homeserver, accessToken, filePath)
{
    const fileName = basename(filePath)
    const mimeType = infer_mime_type(filePath)
    const bytes = await readFile(filePath)
    const uploadUrl = new URL(matrix_api_base(homeserver) + '/_matrix/media/v3/upload')
    uploadUrl.searchParams.set('filename', fileName)

    const response = await fetch(uploadUrl, {
        method: 'POST',
        headers: {
            authorization: 'Bearer ' + accessToken,
            'content-type': mimeType
        },
        body: bytes
    })

    if (!response.ok) {
        throw new Error('Matrix media upload failed for ' + fileName + ' with ' + response.status + ' ' + response.statusText)
    }

    const payload = await response.json()
    if (!payload.content_uri || typeof payload.content_uri !== 'string') {
        throw new Error('Matrix media upload for ' + fileName + ' did not return content_uri')
    }

    const metadata = await stat(filePath)
    return {
        body: fileName,
        mimetype: mimeType,
        size: metadata.size,
        url: payload.content_uri
    }
}

async function send_matrix_room_message(homeserver, accessToken, roomId, content)
{
    const endpoint = matrix_api_base(homeserver)
        + '/_matrix/client/v3/rooms/'
        + encodeURIComponent(roomId)
        + '/send/m.room.message/'
        + matrix_txn_id()

    const response = await fetch(endpoint, {
        method: 'PUT',
        headers: {
            authorization: 'Bearer ' + accessToken,
            'content-type': 'application/json'
        },
        body: JSON.stringify(content)
    })

    if (!response.ok) {
        throw new Error('Matrix send failed with ' + response.status + ' ' + response.statusText)
    }
}

async function post_matrix(entry, baseUrl, state, statePath)
{
    const homeserver = process.env.MATRIX_HOMESERVER
    const accessToken = process.env.MATRIX_ACCESS_TOKEN
    const roomId = process.env.MATRIX_ROOM_ID

    if (!homeserver || !accessToken || !roomId) {
        return { skipped: true, reason: 'Matrix publish env vars not fully set' }
    }

    const channelState = ensure_channel_state(state, entry.id, 'matrix')
    const sentImageUrls = new Set(Array.isArray(channelState.image_urls_sent) ? channelState.image_urls_sent : [])
    const message = format_matrix_message(entry, baseUrl)
    const images = collect_entry_images(entry, baseUrl)
    const uploadedImages = []

    for (const image of images) {
        if (sentImageUrls.has(image.url)) {
            continue
        }

        const filePath = resolve_entry_image_file(entry, image.target)
        const uploaded = await upload_matrix_media(homeserver, accessToken, filePath)
        uploadedImages.push({
            body: image.alt || uploaded.body,
            mimetype: uploaded.mimetype,
            size: uploaded.size,
            source_url: image.url,
            url: uploaded.url
        })
    }

    if (!channelState.text_sent_at) {
        await send_matrix_room_message(homeserver, accessToken, roomId, message)
        channelState.status = 'partial'
        channelState.text_sent_at = new Date().toISOString()
        channelState.image_urls_sent = Array.from(sentImageUrls)
        channelState.url = baseUrl + entry.urlPath
        await write_state(statePath, state)
    }

    for (const image of uploadedImages) {
        if (sentImageUrls.has(image.source_url)) {
            continue
        }

        await send_matrix_room_message(homeserver, accessToken, roomId, {
            msgtype: 'm.image',
            body: image.body,
            url: image.url,
            info: {
                mimetype: image.mimetype,
                size: image.size
            }
        })

        sentImageUrls.add(image.source_url)
        channelState.status = 'partial'
        channelState.image_urls_sent = Array.from(sentImageUrls)
        channelState.url = baseUrl + entry.urlPath
        await write_state(statePath, state)
    }

    channelState.status = 'sent'
    channelState.sent_at = new Date().toISOString()
    channelState.image_urls_sent = Array.from(sentImageUrls)
    channelState.url = baseUrl + entry.urlPath
    return { skipped: false, state_handled: true }
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
                url: baseUrl + entry.urlPath
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
        : await post_matrix(entry, baseUrl, state, statePath)

    if (result.skipped) {
        return { channel, skipped: true, reason: result.reason }
    }

    if (result.state_handled) {
        return { channel, skipped: false }
    }

    const entryState = ensure_entry_state(state, entry.id)
    entryState[channel] = {
        status: 'sent',
        sent_at: new Date().toISOString(),
        url: baseUrl + entry.urlPath
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
    console.log('Seeded publish state for ' + seededCount + ' entries across ' + channels.length + ' channel(s)')
}

for (const entry of entries) {
    if (!entry.body) {
        console.log('Skipping ' + entry.id + ': empty body')
        continue
    }

    if (!less_than_entry_id(entry.id, maxEntryIdExclusive)) {
        console.log('Skipping ' + entry.id + ': not yet publishable')
        continue
    }

    for (const channel of channels) {
        try {
            const result = await publish_channel(channel, entry, state, baseUrl)
            if (result.skipped) {
                console.log('Skipping ' + entry.id + ' for ' + channel + ': ' + result.reason)
            }
            else {
                console.log('Published ' + entry.id + ' to ' + channel)
                await write_state(statePath, state)
            }
        }
        catch (error) {
            hadError = true
            console.error('Failed publishing ' + entry.id + ' to ' + channel + ':', error)
        }
    }
}

if (hadError) {
    process.exitCode = 1
}
