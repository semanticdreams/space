import { posix } from 'node:path'

function is_blank(line)
{
    return /^\s*$/.test(line)
}

function is_list_item(line)
{
    return /^\s*(?:[-*+]|\d+\.)\s+/.test(line)
}

function strip_list_marker(line)
{
    return line.replace(/^\s*(?:[-*+]|\d+\.)\s+/, '')
}

function is_ordered_list_item(line)
{
    return /^\s*\d+\.\s+/.test(line)
}

function normalize_base_url(url)
{
    return url.replace(/\/+$/, '')
}

function entry_heading_anchor(entry)
{
    return `_${entry.id}`
}

function resolve_entry_target_url(entry, target, baseUrl)
{
    const normalizedBaseUrl = normalize_base_url(baseUrl)

    if (/^[a-z]+:/i.test(target)) {
        return target
    }

    if (target.startsWith('#')) {
        return `${normalizedBaseUrl}${entry.urlPath}${target}`
    }

    if (target.startsWith('/')) {
        return `${normalizedBaseUrl}${target}`
    }

    const entrySourcePath = `/dev/devlog/${entry.id}`
    const resolvedPath = posix.normalize(posix.join(posix.dirname(entrySourcePath), target))
    return `${normalizedBaseUrl}${resolvedPath.startsWith('/') ? resolvedPath : `/${resolvedPath}`}`
}

function parse_bracket_content(source, startIndex, openChar, closeChar)
{
    if (source[startIndex] !== openChar) {
        return null
    }

    let depth = 0
    let content = ''

    for (let index = startIndex; index < source.length; index += 1) {
        const char = source[index]

        if (char === '\\') {
            if (index + 1 >= source.length) {
                return null
            }

            if (depth > 0) {
                content += source[index + 1]
            }

            index += 1
            continue
        }

        if (char === openChar) {
            depth += 1
            if (depth > 1) {
                content += char
            }
            continue
        }

        if (char === closeChar) {
            depth -= 1
            if (depth === 0) {
                return {
                    content,
                    nextIndex: index + 1
                }
            }

            if (depth < 0) {
                return null
            }

            content += char
            continue
        }

        if (depth > 0) {
            content += char
        }
    }

    return null
}

function parse_code_span(source, startIndex)
{
    if (source[startIndex] !== '`') {
        return null
    }

    let fenceLength = 0
    while (source[startIndex + fenceLength] === '`') {
        fenceLength += 1
    }

    const fence = '`'.repeat(fenceLength)
    const endIndex = source.indexOf(fence, startIndex + fenceLength)
    if (endIndex === -1) {
        return null
    }

    return {
        text: source.slice(startIndex, endIndex + fenceLength),
        nextIndex: endIndex + fenceLength
    }
}

function parse_link_or_image(source, startIndex, entry, baseUrl)
{
    const isImage = source[startIndex] === '!' && source[startIndex + 1] === '['
    const labelStart = isImage ? startIndex + 1 : startIndex

    if (source[labelStart] !== '[') {
        return null
    }

    const label = parse_bracket_content(source, labelStart, '[', ']')
    if (!label || source[label.nextIndex] !== '(') {
        return null
    }

    const destination = parse_bracket_content(source, label.nextIndex, '(', ')')
    if (!destination) {
        return null
    }

    if (isImage) {
        return {
            text: '',
            nextIndex: destination.nextIndex
        }
    }

    const url = resolve_entry_target_url(entry, destination.content.trim(), baseUrl)
    const renderedLabel = render_inline_text(label.content, entry, baseUrl).trim()
    return {
        text: renderedLabel ? `${renderedLabel}: ${url}` : url,
        nextIndex: destination.nextIndex
    }
}

function render_inline_text(source, entry, baseUrl)
{
    let output = ''

    for (let index = 0; index < source.length;) {
        const codeSpan = parse_code_span(source, index)
        if (codeSpan) {
            output += codeSpan.text
            index = codeSpan.nextIndex
            continue
        }

        const image = parse_link_or_image(source, index, entry, baseUrl)
        if (image) {
            output += image.text
            index = image.nextIndex
            continue
        }

        if (source[index] === '[') {
            const link = parse_link_or_image(source, index, entry, baseUrl)
            if (link) {
                output += link.text
                index = link.nextIndex
                continue
            }
        }

        if (source[index] === '\\' && index + 1 < source.length) {
            output += source[index + 1]
            index += 2
            continue
        }

        output += source[index]
        index += 1
    }

    return output
}

function render_paragraph(lines, entry, baseUrl)
{
    return lines
        .map((line) => render_inline_text(line, entry, baseUrl).trimEnd())
        .filter((line) => line.length > 0)
        .join('\n')
}

function render_list(lines, entry, baseUrl)
{
    const rendered = []
    let currentItem = []
    let currentMarker = '-'

    function flush_item()
    {
        if (currentItem.length === 0) {
            return
        }

        const paragraph = render_paragraph(currentItem, entry, baseUrl)
        if (paragraph.length > 0) {
            rendered.push(`${currentMarker} ${paragraph}`)
        }
        currentItem = []
    }

    for (const line of lines) {
        if (is_list_item(line)) {
            flush_item()
            currentMarker = is_ordered_list_item(line) ? '1.' : '-'
            currentItem.push(strip_list_marker(line))
            continue
        }

        currentItem.push(line.trim())
    }

    flush_item()
    return rendered.join('\n')
}

function render_blockquote(lines, entry, baseUrl)
{
    return lines
        .flatMap((line) => {
            const quoted = line.replace(/^\s*>\s?/, '')
            return render_inline_text(quoted, entry, baseUrl)
                .split('\n')
                .filter((quotedLine) => quotedLine.length > 0)
                .map((quotedLine) => `> ${quotedLine}`)
        })
        .join('\n')
}

function render_code_fence(lines)
{
    return lines.join('\n')
}

function collect_indented_block(lines, startIndex, predicate)
{
    const block = []
    let index = startIndex

    while (index < lines.length && predicate(lines[index])) {
        block.push(lines[index])
        index += 1
    }

    return { block, nextIndex: index }
}

function render_blocks(lines, entry, baseUrl)
{
    const blocks = []

    for (let index = 0; index < lines.length;) {
        if (is_blank(lines[index])) {
            index += 1
            continue
        }

        if (/^```/.test(lines[index])) {
            const block = [lines[index]]
            index += 1
            while (index < lines.length) {
                block.push(lines[index])
                const closingLine = lines[index]
                index += 1
                if (/^```/.test(closingLine)) {
                    break
                }
            }
            blocks.push(render_code_fence(block))
            continue
        }

        if (/^\s*>/.test(lines[index])) {
            const { block, nextIndex } = collect_indented_block(lines, index, (line) => /^\s*>/.test(line))
            blocks.push(render_blockquote(block, entry, baseUrl))
            index = nextIndex
            continue
        }

        if (is_list_item(lines[index])) {
            const { block, nextIndex } = collect_indented_block(lines, index, (line) => !is_blank(line) && (is_list_item(line) || /^\s{2,}\S/.test(line)))
            blocks.push(render_list(block, entry, baseUrl))
            index = nextIndex
            continue
        }

        const paragraph = []
        while (index < lines.length && !is_blank(lines[index]) && !/^```/.test(lines[index]) && !/^\s*>/.test(lines[index]) && !is_list_item(lines[index])) {
            paragraph.push(lines[index])
            index += 1
        }
        blocks.push(render_paragraph(paragraph, entry, baseUrl))
    }

    return blocks.join('\n\n').trim()
}

export function format_social_body(entry, baseUrl)
{
    return render_blocks(entry.body.replace(/\r\n/g, '\n').split('\n'), entry, normalize_base_url(baseUrl))
}

export function format_social_message(entry, baseUrl)
{
    const normalizedBaseUrl = normalize_base_url(baseUrl)
    return `Devlog ${entry.id}\n${format_social_body(entry, normalizedBaseUrl)}\n\n${normalizedBaseUrl}/dev/devlog#${entry_heading_anchor(entry)}`
}

export function social_renderer_test_exports()
{
    return {
        entry_heading_anchor,
        resolve_entry_target_url,
        render_inline_text
    }
}
