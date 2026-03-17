#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  gh-workflow-debug.sh branch-name <workflow>
  gh-workflow-debug.sh remote-branch-sha <branch>
  gh-workflow-debug.sh latest-run-id --workflow <workflow> --branch <branch> [--sha <sha>]
  gh-workflow-debug.sh first-failed-job-id --run-id <run-id>
  gh-workflow-debug.sh wait-run --workflow <workflow> --branch <branch> [--sha <sha>] [--interval <seconds>] [--timeout <seconds>] [--json]

Commands:
  branch-name    Print a throwaway branch name for the workflow.
  remote-branch-sha Print the current remote SHA for a branch.
  latest-run-id  Print the newest matching GitHub Actions run ID.
  first-failed-job-id Print the first failed job ID from a run.
  wait-run       Poll every N seconds until the matching run completes.

Notes:
  - `wait-run` exits non-zero if no matching run appears before timeout.
  - `wait-run` prints the final run summary in shell or JSON form.
EOF
}

die() {
    echo "error: $*" >&2
    exit 1
}

require_arg() {
    local value="$1"
    local name="$2"
    [ -n "$value" ] || die "missing required argument: $name"
}

require_tool() {
    local tool="$1"
    command -v "$tool" >/dev/null 2>&1 || die "required tool not found: $tool"
}

normalize_sha() {
    local sha="$1"
    if [ -z "$sha" ]; then
        printf '\n'
        return 0
    fi
    if command -v git >/dev/null 2>&1; then
        local resolved=""
        resolved="$(git rev-parse --verify "${sha}^{commit}" 2>/dev/null || true)"
        if [ -n "$resolved" ]; then
            printf '%s\n' "$resolved"
            return 0
        fi
    fi
    printf '%s\n' "$sha"
}

shell_escape_json() {
    local value="$1"
    printf '%s' "$value" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

workflow_stem() {
    local workflow="$1"
    local stem
    stem="$(basename "$workflow")"
    stem="${stem%.*}"
    stem="$(printf '%s' "$stem" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
    [ -n "$stem" ] || die "could not derive workflow stem from: $workflow"
    printf '%s\n' "$stem"
}

branch_name_cmd() {
    local workflow="${1:-}"
    require_arg "$workflow" "<workflow>"
    local stem
    stem="$(workflow_stem "$workflow")"
    printf 'codex/workflow-debug/%s-%s\n' "$stem" "$(date -u +%Y%m%d%H%M%S)"
}

remote_branch_sha_cmd() {
    local branch="${1:-}"
    require_arg "$branch" "<branch>"
    require_tool git
    git ls-remote --heads origin "refs/heads/${branch}" | awk '{print $1}'
}

latest_run_id_cmd() {
    local workflow=""
    local branch=""
    local sha=""

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --workflow)
                workflow="${2:-}"
                shift 2
                ;;
            --branch)
                branch="${2:-}"
                shift 2
                ;;
            --sha)
                sha="${2:-}"
                shift 2
                ;;
            *)
                die "unknown argument: $1"
                ;;
        esac
    done

    require_arg "$workflow" "--workflow"
    require_arg "$branch" "--branch"
    sha="$(normalize_sha "$sha")"

    local args=(
        run list
        --workflow "$workflow"
        --branch "$branch"
        --limit 20
        --json databaseId,headSha,headBranch,status,conclusion,createdAt,url
    )

    if [ -n "$sha" ]; then
        args+=(--commit "$sha")
    fi

    gh "${args[@]}" --jq '.[0].databaseId // empty'
}

first_failed_job_id_cmd() {
    local run_id=""

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --run-id)
                run_id="${2:-}"
                shift 2
                ;;
            *)
                die "unknown argument: $1"
                ;;
        esac
    done

    require_arg "$run_id" "--run-id"

    gh run view "$run_id" --json jobs \
        --jq '.jobs[] | select(.conclusion == "failure" or .conclusion == "timed_out" or .conclusion == "startup_failure") | .databaseId' \
        | head -n 1
}

wait_run_cmd() {
    local workflow=""
    local branch=""
    local sha=""
    local interval="100"
    local timeout="7200"
    local output_json="0"
    local latest_args=()

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --workflow)
                workflow="${2:-}"
                shift 2
                ;;
            --branch)
                branch="${2:-}"
                shift 2
                ;;
            --sha)
                sha="${2:-}"
                shift 2
                ;;
            --interval)
                interval="${2:-}"
                shift 2
                ;;
            --timeout)
                timeout="${2:-}"
                shift 2
                ;;
            --json)
                output_json="1"
                shift
                ;;
            *)
                die "unknown argument: $1"
                ;;
        esac
    done

    require_arg "$workflow" "--workflow"
    require_arg "$branch" "--branch"
    sha="$(normalize_sha "$sha")"

    latest_args=(--workflow "$workflow" --branch "$branch")
    if [ -n "$sha" ]; then
        latest_args+=(--sha "$sha")
    fi

    local start_ts now_ts elapsed run_id status conclusion url
    start_ts="$(date +%s)"

    while true; do
        run_id="$(latest_run_id_cmd "${latest_args[@]}")"
        if [ -n "$run_id" ]; then
            break
        fi

        now_ts="$(date +%s)"
        elapsed="$((now_ts - start_ts))"
        if [ "$elapsed" -ge "$timeout" ]; then
            die "no matching run appeared within ${timeout}s for workflow=$workflow branch=$branch sha=${sha:-<any>}"
        fi

        sleep "$interval"
    done

    while true; do
        status="$(gh run view "$run_id" --json status --jq '.status')"
        if [ "$status" = "completed" ]; then
            conclusion="$(gh run view "$run_id" --json conclusion --jq '.conclusion')"
            url="$(gh run view "$run_id" --json url --jq '.url')"
            if [ "$output_json" = "1" ]; then
                printf '{"run_id":%s,"status":"%s","conclusion":"%s","url":"%s"}\n' \
                    "$run_id" \
                    "$(shell_escape_json "$status")" \
                    "$(shell_escape_json "$conclusion")" \
                    "$(shell_escape_json "$url")"
            else
                printf 'run_id=%s status=%s conclusion=%s url=%s\n' "$run_id" "$status" "$conclusion" "$url"
            fi
            [ "$conclusion" = "success" ] || exit 2
            return 0
        fi

        sleep "$interval"
    done
}

main() {
    require_tool gh

    local command="${1:-}"
    if [ -z "$command" ]; then
        usage
        exit 1
    fi
    shift

    case "$command" in
        branch-name)
            branch_name_cmd "$@"
            ;;
        remote-branch-sha)
            remote_branch_sha_cmd "$@"
            ;;
        latest-run-id)
            latest_run_id_cmd "$@"
            ;;
        first-failed-job-id)
            first_failed_job_id_cmd "$@"
            ;;
        wait-run)
            wait_run_cmd "$@"
            ;;
        -h|--help|help)
            usage
            ;;
        *)
            die "unknown command: $command"
            ;;
    esac
}

main "$@"
