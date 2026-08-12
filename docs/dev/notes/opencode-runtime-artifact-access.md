# OpenCode Runtime Artifact Access

On Linux, Space resolves its app directories in `src/appdirs.cpp` using the XDG
environment variables when present, with these default app-specific paths:

- user data: `~/.local/share/space`
- user config: `~/.config/space`
- user cache: `~/.cache/space`
- logs: `~/.cache/space/log`
- temporary artifacts: `/tmp/space` when Space uses the system temp directory

Internal Space agent runtime artifacts are created under the data directory by
`assets/lua/main.fnl`, including:

- `agent-approvals`
- `agent-opencode`
- `agent-sessions`
- `code`

The repo-local OpenCode supervisor and explorer agents may inspect these Space
runtime artifact trees for debugging internal Space agent behavior. Implementer,
reviewer, planner, and capability-agent external-directory boundaries remain
unchanged; this access is not granted to them.

Secret-looking files remain denied after the broader Space app-dir allow rules
because OpenCode evaluates the last matching permission rule. Do not inspect raw
credentials or files whose names look like auth, token, secret, credential, or
keyring material.

After changing repo-local OpenCode agent permission files, quit and restart
OpenCode so the updated agent frontmatter is loaded.
