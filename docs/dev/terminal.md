# Terminal Widget

- Terminal sessions spawn `/bin/sh` by default; override with `SPACE_TERMINAL_PROGRAM` (whitespace-split) such as `SPACE_TERMINAL_PROGRAM="bash -l" make run`.
- In sandboxed environments where a PTY cannot be created, the widget renders a placeholder grid with a status banner and leaves scrollback navigation disabled so the UI stays stable.
