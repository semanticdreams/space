---
type: dev-note
tags:
  - note
---

# Devlog Social Rendering

This note documents the current design for turning devlog markdown entries into social posts, the problems it fixes, the trade-offs we accepted, and the next steps if this area needs to become more capable.

## Problem

The canonical devlog source lives under `docs/dev/journal/*.md`.

That format is correct for the docs site, but it is not correct as a direct transport format for chat/social targets:

- image markdown such as `![Space Prototype Screenshot](../space-prototype-screenshot1.png)` is valid in the docs, but chat transports need native media payloads rather than raw markdown syntax
- relative links are meaningful relative to the source markdown file, but social targets need absolute public URLs
- the public user-facing destination is the generated devlog index page, not the per-entry markdown page
- different targets can require meaningfully different payload shapes even when they share the same source content

This means the docs markdown should remain the canonical source, but publishing must render it into a target-safe representation instead of reusing the raw source verbatim.

## Current Design

Current files:

- `docs/scripts/publish-devlog.mjs`
- `docs/scripts/devlog-social-renderer.mjs`
- `docs/scripts/test-devlog-social-renderer.mjs`
- `docs/scripts/generate-devlog-index.mjs`

The current flow is:

1. `publish-devlog.mjs` reads each devlog entry from `docs/dev/journal/*.md`.
2. Entry links published to users point at the actual VitePress heading anchor form, currently `/dev/devlog#_<entry-id>`, not at `/dev/devlog/<entry-id>`.
3. `generate-devlog-index.mjs` keeps the public devlog page as the user-facing destination for entries.
4. `devlog-social-renderer.mjs` converts the entry body into channel-safe output.
5. Discord formatting and Matrix formatting are split at the payload boundary.
   - Discord message text suppresses a trailing-link embed with angle brackets and ships images as native webhook embeds.
   - Matrix uploads referenced local image assets first, then sends one text event followed by one `m.image` event per image.

## Rendering Rules

The renderer keeps the source markdown as input and applies explicit rules for the markdown subset currently used in devlog entries.

Important behavior:

- markdown images are removed from the text body
- image URLs are resolved to absolute public URLs so channel-specific publishers can attach them as native media payloads
- markdown links become visible text plus absolute URL
- fenced code blocks are preserved
- simple lists are preserved
- blockquotes are preserved
- inline code spans are preserved
- final entry links use the public devlog heading anchor URL
- Discord wraps the final entry URL in angle brackets so Discord does not create a second preview embed from that link
- Matrix sends a single text event first, then image events, to keep room noise minimal while still using native media messages

Example source markdown:

```md
![Space Prototype Screenshot](../space-prototype-screenshot1.png)
```

Published Discord payload shape:

```json
{
  "content": "Devlog 2025-09-16\n\n<https://spaceui.org/dev/devlog#_2025-09-16>",
  "embeds": [
    {
      "image": {
        "url": "https://spaceui.org/dev/space-prototype-screenshot1.png"
      }
    }
  ]
}
```

Published Matrix event flow:

1. One `m.text` `m.room.message` event with the rendered devlog body and public devlog link.
2. One `m.image` `m.room.message` event per image, referencing uploaded `mxc://` media.

## Why This Design

This is still intentionally a middle-ground design.

Why we did not keep the old approach:

- the original publisher used raw markdown body text in social payloads
- a quick regex rewrite was enough to prove the direction, but it was not robust enough to be the long-term implementation
- trying to force image markdown into social posts produced the wrong user experience and still depended on transport-specific behavior

Why we did not jump straight to a full markdown stack:

- the docs toolchain in this repo does not currently expose a simple direct markdown parser dependency for this script
- pulling in a full parser just for this workflow would add dependency and maintenance work that was not justified by the current content complexity

Why the current solution is acceptable:

- it cleanly separates canonical source content from publish-target rendering
- it fixes the real user-facing failures we saw in production
- it is tested against fragments and real entries
- it is easy to extend further per channel without mutating the canonical markdown

## Trade-offs

This is better than regex rewriting, but it is still not a full CommonMark implementation.

Accepted trade-offs:

- the parser is purpose-built for the markdown subset we currently use in devlog entries
- unusual nested markdown constructs may still render imperfectly
- inline HTML is not treated as a first-class structured format
- Matrix media publishing currently supports local file-backed image markdown, not arbitrary remote image URLs
- the current heading-anchor path depends on VitePress's heading id behavior for date-based headings

This is deliberate. The goal was to make the publisher correct for current content and clean enough to extend, without overbuilding.

## Unsupported Construct Policy

Unsupported or partially supported constructs should follow explicit rules instead of accidental parser behavior.

Current policy:

- images: omit them from rendered text; publish them only through channel-native media payloads when the channel implementation supports that
- nested or unusual markdown combinations: flatten to the nearest plain-text rendering when possible
- inline HTML: treat as plain text, not as structured markup
- reference-style links, tables, and other unsupported markdown forms: leave them as plain text unless a specific renderer rule is added
- remote image URLs in Matrix publishing: fail loudly instead of guessing at download/upload behavior
- constructs that would corrupt the published message shape or destination URL resolution: fail loudly in the publisher rather than silently inventing output

## Current Test Coverage

`docs/scripts/test-devlog-social-renderer.mjs` now covers:

- relative asset URL resolution
- markdown image omission from text bodies
- Discord image embed extraction
- markdown link rendering
- fenced code blocks
- simple lists
- blockquotes
- inline code spans
- Discord full-message formatting with the public devlog anchor URL wrapped in angle brackets
- Matrix full-message formatting with the plain public devlog anchor URL
- fixture-style coverage using complete sample entries from `docs/dev/journal/`
- extracted image metadata needed for Matrix upload

Run with:

```sh
node --test docs/scripts/test-devlog-social-renderer.mjs
```

## Future Improvements

If this system needs to become more capable, the next steps should be:

1. Add richer Matrix image metadata.
   - width and height
   - thumbnails where worthwhile
   - encrypted media if needed by the deployment

2. Consider an intermediate structured representation if channel divergence grows.
   - blocks
   - inline spans
   - resolved URLs
   - image/link/code/list/quote nodes

3. Consider adopting a real markdown AST parser once complexity justifies it.
   - this becomes worthwhile if entries start using more advanced markdown or if several output targets diverge meaningfully

## Guidance

When changing the devlog publisher:

- keep `docs/dev/journal/*.md` as the canonical authoring format
- do not special-case Discord or Matrix by mutating the source markdown
- keep public links pointed at the generated devlog heading anchors
- extend the social renderer and its tests together
- prefer explicit rendering rules over silent magic


## See also

- [Cross Platform](/dev/subsystems/cross-platform)
