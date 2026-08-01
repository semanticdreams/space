# Orca OpenCode Workflow Documentation Design

## Context

Space now keeps its OpenCode configuration in the repository under `.opencode/`, with always-on guidance in `AGENTS.md` and task-specific workflows in `.opencode/skills/**`. Collaborators who want to use the same agent workflow need a repo-visible setup guide instead of relying on a personal VM note.

The source VM note contains useful general setup ideas for local Orca controlling a remote SSH development VM, but it also includes local-only or obsolete material. The guide must omit laptop-specific notification plugin details, the old separate `opencode-config` repository, and `auth.json` copying instructions. It should also make clear that local Orca plus remote SSH is only one supported arrangement; Orca can also run entirely on the remote VM with local Orca used only to view or connect to it.

Existing docs already anticipate this page: `docs/.vitepress/config.mts` links to `/dev/features/opencode-agent-workflow`, but `docs/dev/features/opencode-agent-workflow.md` does not exist yet.

## Explored Approaches

### Approach A: Add a note under `docs/dev/notes/`

This would treat the setup as informal working guidance. It is low-friction, but notes are presented as raw documentation and the existing sidebar link would remain broken.

### Approach B: Fill the existing feature-page target

Create `docs/dev/features/opencode-agent-workflow.md` and link it from the feature indexes. This matches the existing sidebar, gives collaborators a polished canonical page, and keeps the workflow near other Space development tooling and automation docs.

### Approach C: Expand an existing automation page

The daily and weekly automation docs already mention Orca prompts, but they are intentionally scoped to scheduled jobs. Expanding either page would mix general collaborator setup with automation-specific policy.

## Recommended Direction

Use Approach B. Create the missing `docs/dev/features/opencode-agent-workflow.md` page and add it to `docs/dev/features/index.md` and `docs/dev/index.md`. Leave `docs/.vitepress/config.mts` unchanged because it already contains the target link.

## Design

### Architecture

- Add one collaborator-facing feature page for the Space Orca/OpenCode workflow.
- Structure the page around setup options, a local Orca + remote SSH checklist, the remote-Orca alternative, Space-specific workflow expectations, and explicit exclusions.
- Link to official Orca documentation for general platform behavior:
  - `https://www.onorca.dev/docs/ways-to-run`
  - `https://www.onorca.dev/docs/ssh`
  - `https://www.onorca.dev/docs/remote-servers`
- Keep Space-specific guidance focused on repository conventions: `AGENTS.md`, repo-local `.opencode/**`, restart requirements after `.opencode/**` changes, branch/PR workflow, and validation expectations.

### User-Facing Behavior

Collaborators should be able to open the docs site, find **OpenCode Agent Workflow**, and understand:

- that Orca/OpenCode use is optional and this is one possible local workflow;
- how to prepare a generic remote SSH environment for Space work;
- how to connect Orca to a remote checkout;
- why they should rely on repo-local `.opencode/**` instead of a global config repository;
- what local-only setup snippets from the personal VM note are intentionally not part of the shared guide;
- which Space validation commands and repository policies matter once agents start making changes.

### Error Handling and Caveats

The page should fail closed in its advice: do not tell collaborators to copy credential files, rely on host-specific plugins, or revive obsolete global config. Troubleshooting should stay general, such as checking forwarded SSH agent state or testing GitHub SSH access, without prescribing private machine paths.

### Testing

Because this is documentation-only, validation should include a focused review of links and exclusions plus a VitePress docs build. The implementation handoff should verify that only the new feature page and docs indexes changed, and that `.vitepress/config.mts` remains unchanged.

## Scope

In scope:

- Creating the canonical OpenCode Agent Workflow feature page.
- Adding discoverability links from developer feature indexes.
- Incorporating general remote-SSH VM setup ideas from the external note.
- Linking to official Orca setup, SSH, and remote-server docs.

Out of scope:

- Editing `.opencode/**` or global OpenCode configuration.
- Documenting the laptop-specific notification plugin.
- Referencing the obsolete separate `opencode-config` repository as an active requirement.
- Copying or documenting `auth.json` migration.
- Changing runtime code, tests, package dependencies, or docs site configuration.

## Self-Review Notes

- No placeholders remain.
- The recommended target fixes an existing sidebar link without changing docs configuration.
- The scope explicitly excludes the obsolete and local-only setup details the user called out.
