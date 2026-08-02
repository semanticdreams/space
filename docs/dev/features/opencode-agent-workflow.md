# OpenCode Agent Workflow

This page documents Space's shared Orca / OpenCode workflow for collaborators using the repo-local configuration. It describes how to set up a working agent environment, what the repository expects from agent-driven changes, and which pieces of the personal VM setup note are intentionally excluded from this shared guide.

## Official Orca documentation

Orca and OpenCode provide the agent runtime and development environment. The official documentation covers platform installation, session management, and remote-server workflows:

- [Ways to run Orca](https://www.onorca.dev/docs/ways-to-run)
- [Orca SSH](https://www.onorca.dev/docs/ssh)
- [Orca remote servers](https://www.onorca.dev/docs/remote-servers)

## Supported setups

Space does not require one specific arrangement. Two patterns are supported:

- **Local Orca plus remote SSH checkout.** You run Orca on your local machine, connect to a remote development VM over SSH, and open the Space checkout on that VM. This keeps the heavy build toolchain on the remote host while your local Orca session orchestrates OpenCode.
- **Orca running on the remote VM.** You install Orca directly on the remote development machine and use a local Orca session only to view or connect to that remote session. This works well when your local environment is thin or when you prefer to keep everything on one host.

The local Orca plus remote SSH checklist below is one possible path; it is not a project requirement. Choose whichever arrangement fits your environment.

## Local Orca plus remote SSH checklist

If you choose the local-Orca-plus-remote-SSH setup, work through these points:

1. **Remote VM reachable.** Confirm you can SSH into the remote VM from your local machine.
2. **Build and dev tools.** Install common tooling on the remote VM: `git`, `nodejs` and `npm`, `python3`, `make`, `g++`, `curl`, and `clangd`. These are typically available through the system package manager.
3. **OpenCode on the remote VM.** Install OpenCode and make sure it is on `PATH` for non-interactive SSH sessions so that Orca can invoke it automatically.
4. **GitHub SSH access.** Configure SSH key access for GitHub on the remote VM so the agent can push branches and create pull requests. Test with `ssh -T git@github.com`.
5. **Clone Space on the remote VM.** Clone the repository into a working directory the SSH user can write to.
6. **Add the host in Orca.** Add the SSH host and repository path in Orca's remote-server workflow so it can open the checkout.
7. **Rely on the checked-out repository.** Once the checkout is opened, the agent reads `AGENTS.md` and `.opencode/**` from the repository itself — no external configuration repository is needed.
8. **Final checks.** Run `command -v git node npm clangd opencode` on the remote VM to confirm the expected tools are available, then verify SSH connectivity with `ssh -T git@github.com`.

## Remote-VM Orca alternative

When running Orca entirely on the remote VM fits your environment better, install Orca on that host and launch your agent sessions there. Use your local Orca session only as a viewer or connector — some collaborators keep a local Orca window open that connects to the remote instance.

See Orca's [remote servers](https://www.onorca.dev/docs/remote-servers) documentation for details on managing remote Orca instances.

## Space workflow expectations

Once your agent environment is connected to a Space checkout, these repository conventions apply:

- **`AGENTS.md`** is the always-on repository guidance. Agents read it on startup and follow its rules for every session. It covers branch conventions, build commands, test invocation, coding style, and project structure.
- **`.opencode/**`** is the repo-local source for Space agents, skills, and OpenCode configuration. It includes agent definitions, skill files that provide specialized guidance for Fennel, UI, testing, and graph work, and the OpenCode configuration file. This in-repo configuration is canonical for this repository — no separate global config repository is needed.
- **Restart OpenCode after `.opencode/**` changes.** When you add or modify agents, skills, or configuration under `.opencode/`, restart OpenCode so the updated definitions and workflow instruction changes take effect. OpenCode loads these files at startup and does not hot-reload them.
- **Follow repository validation expectations from `AGENTS.md`.** Agents must respect the validation ladder: for Fennel work, run compile checks first, then constraints, then focused tests, then the broader suite. Required validation failures are debugging tasks, not items to bypass.
- **Full Space validation.** When a change touches code that could affect the broader system, run the full test suite:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
  ```

- **Fennel-facing work** must use the project-native Fennel validation ladder from `AGENTS.md`. Do not use system `fennel`, `fennel-ls`, `fnlfmt`, or ad-hoc evaluation as validation oracles. Use `tools.fennel-check`, constraints, and the test harness instead.
- **Required validation failures**: see [Validation continuation and current base](#validation-continuation-and-current-base) for the full contract.

## Validation continuation and current base

Required validation failures are active debugging work, not a terminal workflow
state. When a required suite fails, agents capture the failing command, failing
tests, relevant output, current branch state, and `git status --porcelain`;
invoke `systematic-debugging`; and continue investigating even when the failure
appears unrelated, flaky, timing-dependent, or environmental.

Repository fixes, generated-file repairs, and conflict resolutions go through
`implementer` → `reviewer` → pass before commit. Agents rerun validation from a
clean tree and proceed only when the required suite is green, or when systematic
debugging establishes a true human-input blocker such as missing credentials,
inaccessible infrastructure, an unsafe git-history decision, unreproducible
behavior after reasonable evidence gathering, or a product/API/data/architecture
choice.

Before final validation, PR creation, or a ready-to-merge claim, agents fetch
`origin` and evaluate the branch against current `origin/main`. If the branch is
behind, they use a safe merge from `origin/main` when permitted, route resulting
fixes through review, and rerun validation. Agents do not rebase or force-push
unless the human explicitly requests it.

## Branch and pull request policy

All agent-driven changes follow these branch and PR rules. The canonical source
repository is `https://github.com/semanticdreams/space2`.

### Pre-PR current-base validation

- Pull requests target `main`.
- Final validation and PR creation require a branch that is current with `origin/main`. Diff/base checks always use `origin/main`, not local `main`. Local `main` may be stale or contain unrelated local commits.
- Before final validation, PR creation, or a ready-to-merge claim, fetch `origin` and evaluate the branch against current `origin/main`. If the branch is behind, use a safe merge from `origin/main` when permitted, route resulting fixes through review, and rerun validation.
- Do not push directly to `main`. Always work on a feature branch and open a pull request.

### Post-PR merge queue

After implementation is complete — reviewed, committed, all tests passing, and
the tree clean — the default integration action is to push the current branch,
create a pull request targeting `main`, and enable auto-merge to hand the PR off
to GitHub's merge queue.

After the PR is open and queued:

- **Do not update the branch** solely because another PR merged to `main`. The
  merge queue's merge-group checks are the post-PR integration freshness gate.
- **Stale-branch update loops are forbidden.** The queue, not the agent, owns
  post-PR freshness.
- **Queue failures are actionable blockers.** Merge conflicts and merge-group
  required-check failures trigger `systematic-debugging`. Repository fixes follow
  the standard `implementer` → `reviewer` → pass flow. After reviewed fixes are
  committed and validation passes against current `origin/main`, requeue the PR.
- If merge queue is not enabled or cannot be verified, agents report
  `HUMAN_DECISION_REQUIRED` with the exact GitHub setting needed and do not
  enter a stale-branch polling loop.

### GitHub admin requirement

A repository admin must enable merge queue for `main` in the GitHub branch
ruleset, ensure the required `test` check runs for merge-group candidates, and
relax any rule that forces every PR branch to be updated after `main` moves if
that rule blocks queue entry.

If required validation fails after implementation, review, or commit, see [Validation continuation and current base](#validation-continuation-and-current-base). Do not finish, push, create a PR, merge, or clean up the branch while validation is red.

## Exclusions

This shared Space guide intentionally does not document:

- Laptop-specific notify plugin setup — this varies across machines and is not a project requirement.
- The obsolete separate `opencode-config` repository as an active requirement — Space configuration lives in `.opencode/**` within the repository.
- Copying, migrating, or sharing `auth.json` — credential files are personal and should never be shared or checked into the repository.
