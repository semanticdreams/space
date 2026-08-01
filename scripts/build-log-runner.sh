#!/usr/bin/env bash
set -u

usage() {
    echo "usage: build-log-runner.sh --log <path> --label <label> [--tail-lines <n>] -- <command> [args...]" >&2
}

LOG_PATH=""
LABEL="build"
TAIL_LINES="${SPACE_BUILD_LOG_TAIL_LINES:-80}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --log)
            if [[ $# -lt 2 || -z "${2:-}" ]]; then
                usage
                exit 2
            fi
            LOG_PATH="$2"
            shift 2
            ;;
        --label)
            if [[ $# -lt 2 || -z "${2:-}" ]]; then
                usage
                exit 2
            fi
            LABEL="$2"
            shift 2
            ;;
        --tail-lines)
            if [[ $# -lt 2 || -z "${2:-}" ]]; then
                usage
                exit 2
            fi
            TAIL_LINES="$2"
            shift 2
            ;;
        --)
            shift
            break
            ;;
        *)
            usage
            exit 2
            ;;
    esac
done

if [[ -z "${LOG_PATH}" || $# -eq 0 ]]; then
    usage
    exit 2
fi

if ! [[ "${TAIL_LINES}" =~ ^[0-9]+$ ]] || [[ "${TAIL_LINES}" -lt 1 ]]; then
    echo "error: --tail-lines must be a positive integer" >&2
    exit 2
fi

LOG_DIR="$(dirname "${LOG_PATH}")"
LOG_BASENAME="$(basename "${LOG_PATH}")"

if ! mkdir -p "${LOG_DIR}"; then
    echo "error: failed to create log directory: ${LOG_DIR}" >&2
    exit 2
fi

LOG_DIR_ABS="$(cd "${LOG_DIR}" && pwd)"
LOG_ABS="${LOG_DIR_ABS}/${LOG_BASENAME}"

if ! : > "${LOG_ABS}"; then
    echo "error: failed to initialize log file: ${LOG_ABS}" >&2
    exit 2
fi

printf '==> %s\n' "${LABEL}"
printf 'Log: %s\n' "${LOG_ABS}"
printf 'Running quietly; full transcript is being written to the log.\n'

"$@" >"${LOG_ABS}" 2>&1
STATUS=$?

if [[ "${STATUS}" -eq 0 ]]; then
    printf 'OK: %s complete. Full log: %s\n' "${LABEL}" "${LOG_ABS}"
    exit 0
fi

{
    printf 'FAILED: %s exited with status %d. Full log: %s\n' "${LABEL}" "${STATUS}" "${LOG_ABS}"
    printf '%s\n' "--- Last ${TAIL_LINES} lines of ${LOG_ABS} ---"
    tail -n "${TAIL_LINES}" "${LOG_ABS}" 2>/dev/null || true
    printf '%s\n' "--- End log tail ---"
} >&2

exit "${STATUS}"
