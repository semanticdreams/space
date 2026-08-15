# Workflow-backed agent sessions

Sidebar agent chats are durable workflow runs. One sidebar chat equals one long-lived workflow run created from the default agent workflow definition. The workflow run id is the current durable session identity used by the sidebar, graph, and agent runtime.

## Architecture

- **One chat, one run:** Creating a sidebar chat starts a long-lived workflow run with `:agent-session?` in run context. The run remains alive across user turns.
- **Turns are wait/resume cycles:** The default agent workflow waits for `:agent-user-input`. `run-turn` appends the user message, starts the turn controller, and resumes the waiting workflow step with the user's input. After the provider turn starts, the workflow waits again for the next turn.
- **Events are the transcript source of truth:** Session state is projected from workflow events. There is no separate transcript cache for current sidebar chats.
- **Compatibility facade:** `llm.agent.workflow-runner` preserves the sidebar runner API: `create-session`, `get-session`, `list-sessions`, `run-turn`, `cancel-turn`, `delete-session`, `flush`, and `drop`. Callers keep the existing chat-panel behavior while persistence moves to workflows.
- **Graph parity:** Workflow graph nodes expose the same workflow run/session state through `WorkflowStore`. Graph maps and node adapters present workflow definitions, runs, run steps, and events; they do not own agent session state.
- **Explicit migration only:** Startup does not read old `agent-sessions/*.json` files. Legacy JSON sessions become workflow runs only when the migration tool is invoked explicitly.

## Event schema

Agent session projection consumes these workflow event kinds:

- `:agent-session-created`
  - Required: `:kind`, `:data` table.
  - `:data` must include `:agent-id` for new sessions and may include initial `:data` session data, migration metadata such as `:legacy-agent-session-id`, and `:created-at`.
- `:agent-status-changed`
  - Required: `:kind`, `:status`.
  - Optional: `:data` table and `:created-at`. The runner also mirrors current status into run context for summaries.
- `:agent-item-appended`
  - Required: `:kind`, `:item` table, and `:item.id` string.
  - The item is appended and duplicate item ids fail projection/append validation.
- `:agent-item-upserted`
  - Required: `:kind`, `:item` table, and `:item.id` string.
  - Existing items with the same id are replaced; otherwise the item is appended.
- `:agent-item-updated`
  - Required: `:kind`, `:item-id` string, and `:updates` table.
  - The referenced item must already exist; updates are merged into the projected item.

Event `:created-at` timestamps, when present on relevant events, advance the projected session `:updated-at` value. `:agent-session-data-updated` is also emitted by the runtime when mutable session data is persisted.

## Migration command

Run migration against the Space user data directory that contains legacy `agent-sessions/*.json` files:

```bash
./build/space -m tools.agent-session-migrate:main -- --base-dir <space-user-data-dir>
```

The command prints counts and a mapping from each legacy session id to the workflow run id:

```text
migrated: <count>
archived: <count>
archive-dir: <space-user-data-dir>/agent-sessions-archive/<timestamp>
mapping:
  <legacy-session-id> -> <workflow-run-id>
```

Each valid legacy session is converted into a workflow run with provider/runtime continuity metadata preserved in run context and projected session data, including OpenCode/provider session ids, artifact and report paths, timestamps, and legacy audit ids. After a file is durably converted, the original JSON file is moved into the printed archive directory under `agent-sessions-archive/<timestamp>/`.

Migration is idempotent. If a workflow run already exists for a legacy session id, the tool verifies that the projected workflow-backed session matches the legacy file before archiving that file again. Malformed JSON, missing required fields, incompatible existing runs, or archive failures fail loudly and exit nonzero rather than silently skipping data.
