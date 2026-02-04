# OpenAI API docs

This folder holds the OpenAI API reference and guides we mirror for engine integrations. Use `rg "POST /responses" doc/openai` (or any verb/path) from the repo root to jump straight to an endpoint file.

## API reference map
- **Responses & chat**: `api-reference/responses/` (core `/responses` API), `api-reference/responses-streaming/` (server-sent events), `api-reference/chat/` and `api-reference/chat-streaming/` (legacy chat completions).
- **Assistants platform**: `api-reference/assistants/`, `api-reference/threads/`, `api-reference/messages/`, `api-reference/runs/`, `api-reference/run-steps/`, plus streaming event shapes in `api-reference/assistants-streaming/`.
- **Realtime**: main doc at `api-reference/realtime.md`, session lifecycle in `api-reference/realtime-sessions/`, client event payloads in `api-reference/realtime-client-events/`, and server events in `api-reference/realtime-server-events/`.
- **Files, uploads, and vector stores**: `api-reference/files/`, resumable uploads in `api-reference/uploads/`, vector store management in `api-reference/vector-stores/`, per-file ops in `api-reference/vector-stores-files/`, and batch ingestion in `api-reference/vector-stores-file-batches/`.
- **Models, generation, and grading**: `api-reference/models/`, `api-reference/completions/`, `api-reference/images/`, `api-reference/audio/`, `api-reference/embeddings/`, `api-reference/moderations/`, and graders in `api-reference/graders/`.
- **Batches and usage**: batch job lifecycle in `api-reference/batch/`, usage metrics under `api-reference/usage/`.
- **Fine-tuning and evals**: `api-reference/fine-tuning/` (including DPO/RFT inputs) and evaluation endpoints in `api-reference/evals/`.
- **Projects, auth, and admin**: project metadata and membership in `api-reference/projects/`, project users and service accounts under `api-reference/project-users/` and `api-reference/project-service-accounts/`, rate limits in `api-reference/project-rate-limits/`, keys in `api-reference/project-api-keys/` and `api-reference/admin-api-keys/`, certificates in `api-reference/certificates/`, invites in `api-reference/invite/`, audit logs in `api-reference/audit-logs/`, and user details in `api-reference/users/`. See `api-reference/administration.md` for a high-level admin overview.

## Guides
- Quick starts live at `guides/quickstart.md` and `guides/assistants/quickstart.md`; `guides/advanced-usage.md` covers general tuning tips.
- Assistants deep dives sit under `guides/assistants/` (overview, tools, whats-new, etc.).
- Actions are documented in `guides/actions/` (intro, auth, production notes, sending files, data retrieval, and the actions library).
- General topic guides (structured outputs, retrieval, streaming, vision, safety, prompt caching, latency, etc.) are in `guides/guides/`.
- Deprecations are tracked in `guides/deprecations.md`; language/library pointers live in `guides/libraries.md`.
