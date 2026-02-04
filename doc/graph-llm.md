# Graph LLM Strategy

This document outlines how to complete graph-based, forkable LLM conversations
using the existing graph/view architecture and OpenAI integration.

## Goals

- Represent conversations as a graph to allow branching/forking.
- Keep graph nodes decoupled from views.
- Support OpenAI request/response flows and tool calls.
- Make conversation state persistent and replayable.

## Core data model

Define canonical node types and keep state on nodes:

- `llm-conversation`: owns conversation metadata.
- `llm-message`: role/name/content + optional tool metadata.
- `llm-tool-call`: captures tool invocation (name, args, call id).
- `llm-tool-result`: captures tool result payload and links back to a call.
- `llm-conversations`: browser for saved conversations under `user-data-dir/llm`.

Edges should encode the message chain (parent/prev) and forks. A fork is an
additional edge from a message to a new message chain. The active branch is
implicit: the message node you trigger from is the branch head.

## Branch selection and flattening

- The `llm-message` node traverses the graph to linearize the branch by walking
  from the triggered message to its conversation root.
- Forking creates a new child chain off any message; new messages attach to the
  message node that initiated the request.

## OpenAI integration (existing client)

The OpenAI client lives in `assets/lua/openai.fnl`. It supports:

- `create-response` (POST `/responses`)
- `get-response`, `delete-response`, `list-input-items`
- non-streaming responses only (streaming SSE is intentionally rejected)

Integration strategy:

- Build a request payload from the linearized branch and pass it to
  `OpenAI.create-response` (done inside `llm-message`).
- Store `response_id` on the message node created from the response.
- For tools, include the `tools` payload (the client auto-adds the beta header),
  create `llm-tool-call`/`llm-tool-result` nodes, execute tool calls locally,
  then run a follow-up model request using the tool output items.

## Views and signals

Views must be constructors only; no per-instance builders in nodes. Views should:

- Subscribe to node signals (`items-changed`, `message-changed`, etc.).
- Render the active branch by default and allow branch switching.
- Provide controls for “fork here” and “switch branch.”

## Persistence

Persist LLM conversations, messages, and item links in the LLM store under
`appdirs.user-data-dir / llm /`. Graph nodes are adapters and should not
write separate `graph/node-data` files for LLM conversations or messages.

## Suggested implementation steps

1. Add/confirm node types + signals for conversation, message, and tool nodes.
2. Implement branch selection + linearization helper.
3. Implement OpenAI client module and request/response wiring.
4. Add tool dispatcher + tool result nodes.
5. Update views to render and control branching.
6. Add persistence and replay.
