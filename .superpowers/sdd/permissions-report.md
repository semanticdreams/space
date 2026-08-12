Permissions Report: routine Git inspection allows

Implemented
- Inspected `.opencode/agents/*.md` Git-related bash permissions.
- Added explicit allow entries for routine read-only Git inspection commands to the primary supervisor and implementation agent:
  - `git status*`
  - `git diff*`
  - `git log*`
  - `git rev-parse*`
  - `git remote get-url*`
  - `git branch --show-current*`
  - `git diff --staged*`
- Kept privileged and dangerous Git/GitHub operations denied after the broad/read-only allows so last-match permission evaluation preserves hard safety gates.
- Left guarded wrapper agents (`git-integrator`, `github-operator`) as the only path for privileged integration operations.

Validation Evidence
- Basic frontmatter/YAML parse check:
  `python3 - <<'PY' ... yaml.safe_load(frontmatter) ... PY`
  Result: `frontmatter parse ok: 11 agent files`.

Constraint Impact
- not applicable: OpenCode agent permission metadata only.

Files Changed
- `.opencode/agents/implementer.md`
- `.opencode/agents/supervisor.md`
- `.superpowers/sdd/permissions-report.md`

Concerns
- The reported recent blocker was the guarded git-integrator trusted-remote check, not an OpenCode shell prompt. The repository now reports origin as `https://github.com/semanticdreams/space2`, so the wrapper should accept it if its trusted-remote list includes that corrected URL.

Review Fix R1-1

Implemented
- Added implementer denies for direct privileged integration commands that must remain wrapper-only:
  - `git fetch*`, `git pull*`, `git merge*`
  - `git branch -d*`, `git branch --delete*`
  - `git -C * fetch*`, `git -C * pull*`, `git -C * merge*`
  - `git -C * branch -d*`, `git -C * branch --delete*`
- Kept read-only Git inspection allow entries intact and before the later denies.

Validation Evidence
- Basic frontmatter/YAML parse check:
  `python3 - <<'PY' ... yaml.safe_load(frontmatter) ... PY`
  Result: `frontmatter parse ok: 11 agent files`.

Coverage Rationale
- The parse check covers all project agent frontmatter after the permission-key additions. Diff review confirms the added rules are later than the read-only allow entries, preserving last-match denial for integration operations.

Constraint Impact
- not applicable: OpenCode agent permission metadata only.

Files Changed
- `.opencode/agents/implementer.md`
- `.superpowers/sdd/permissions-report.md`

Self-Review Findings
- Confirmed no production source/test files were edited and no permissions were broadened.
