#!/usr/bin/env bash
#
# Ask GPT-Pro - One-shot consultation with ChatGPT Pro Extended via gpt-pro-relay
#
# Sends a question or task to GPT-5 Pro Extended on macmini (directly when this
# script runs on macmini, or over SSH otherwise) and returns the response. GPT-5
# Pro Extended performs deep reasoning with built-in web research.
#
# Usage:
#   ask-gpt-pro.sh [--timeout SECONDS] [question...]
#
# Output:
#   stdout: GPT-Pro's response (for Claude to read)
#   stderr: Status/debug info (run_id, transport, log paths)
#
# Storage:
#   Project-local: .humanize/skill/<unique-id>/{input,output,metadata}.md
#   Cache: ~/.cache/humanize/<sanitized-path>/skill-<unique-id>/gpt-pro-run.{cmd,out,log}
#

set -euo pipefail

# ========================================
# Source Shared Libraries
# ========================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

# Portable timeout wrapper (used to bound the direct-mode call)
source "$SCRIPT_DIR/portable-timeout.sh"

# Shared project-root resolver (CLAUDE_PROJECT_DIR -> git toplevel, realpath-canonical)
source "$SCRIPT_DIR/../hooks/lib/project-root.sh"

# ========================================
# Default Configuration
# ========================================

# gpt-pro-relay's worker timeout is fixed at 60 min; this is the wall-clock
# we'll spend in the polling loop. Cap at 3600s.
DEFAULT_TIMEOUT=3600
ASK_TIMEOUT="$DEFAULT_TIMEOUT"
SSH_HOST="${HUMANIZE_GPT_PRO_HOST:-macmini}"

# ========================================
# Help
# ========================================

show_help() {
    cat << 'HELP_EOF'
ask-gpt-pro - One-shot deep-reasoning consultation with ChatGPT Pro Extended

USAGE:
  /humanize:ask-gpt-pro [OPTIONS] <question or task>

OPTIONS:
  --timeout <SECONDS>  Overall wall-clock timeout for the run (default: 3600)
  -h, --help           Show this help message

DESCRIPTION:
  Sends a one-shot question or task to GPT-5 Pro Extended via gpt-pro-relay.
  If run on macmini, calls gpt-pro-relay directly. Otherwise, submits via
  SSH using the resilient polling pattern (short SSH sessions, exponential
  backoff on transport drops) so flaky networks don't kill the run.

  GPT-5 Pro Extended performs deep reasoning with built-in web research,
  typically 5-20 minutes per call. The response is saved to
  .humanize/skill/<unique-id>/output.md for reference.

EXAMPLES:
  /humanize:ask-gpt-pro What are the latest best practices for Rust error handling?
  /humanize:ask-gpt-pro --timeout 1800 Review recent CVEs for OpenSSL 3.x

ENVIRONMENT:
  HUMANIZE_GPT_PRO_HOST
    SSH host to reach gpt-pro-relay (default: macmini). Ignored when this
    script runs on the gpt-pro-relay host itself.
HELP_EOF
    exit 0
}

# ========================================
# Parse Arguments
# ========================================

QUESTION_PARTS=()
OPTIONS_DONE=false

while [[ $# -gt 0 ]]; do
    if [[ "$OPTIONS_DONE" == "true" ]]; then
        QUESTION_PARTS+=("$1")
        shift
        continue
    fi
    case $1 in
        -h|--help)
            show_help
            ;;
        --)
            OPTIONS_DONE=true
            shift
            ;;
        --timeout)
            if [[ -z "${2:-}" ]]; then
                echo "Error: --timeout requires a number argument (seconds)" >&2
                exit 1
            fi
            if ! [[ "$2" =~ ^[1-9][0-9]*$ ]]; then
                echo "Error: --timeout must be a positive integer (seconds), got: $2" >&2
                exit 1
            fi
            ASK_TIMEOUT="$2"
            shift 2
            ;;
        -*)
            echo "Error: Unknown option: $1" >&2
            echo "Use --help for usage information" >&2
            exit 1
            ;;
        *)
            QUESTION_PARTS+=("$1")
            OPTIONS_DONE=true
            shift
            ;;
    esac
done

QUESTION="${QUESTION_PARTS[*]}"

# ========================================
# Validate Prerequisites
# ========================================

if [[ -z "$QUESTION" ]]; then
    echo "Error: No question or task provided" >&2
    echo "" >&2
    echo "Usage: /humanize:ask-gpt-pro [OPTIONS] <question or task>" >&2
    echo "" >&2
    echo "For help: /humanize:ask-gpt-pro --help" >&2
    exit 1
fi

# Detect transport: direct on macmini, SSH everywhere else
DIRECT_MODE=0
if [[ "$(hostname -s 2>/dev/null || true)" == "$SSH_HOST" ]]; then
    DIRECT_MODE=1
fi

if (( DIRECT_MODE )); then
    if ! command -v gpt-pro-relay &>/dev/null; then
        echo "Error: 'gpt-pro-relay' command not found on $SSH_HOST" >&2
        echo "" >&2
        echo "Try the absolute venv path or recreate ~/.local/bin/gpt-pro-relay" >&2
        exit 1
    fi
else
    if ! command -v ssh &>/dev/null; then
        echo "Error: 'ssh' command not found; cannot reach gpt-pro-relay on $SSH_HOST" >&2
        exit 1
    fi
fi

# ========================================
# Detect Project Root
# ========================================

PROJECT_ROOT="$(resolve_project_root)" || {
    echo "Error: Cannot determine project root." >&2
    echo "  Set CLAUDE_PROJECT_DIR or run inside a git repository." >&2
    exit 1
}

# ========================================
# Create Storage Directories
# ========================================

TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
UNIQUE_ID="${TIMESTAMP}-$$-$(head -c 4 /dev/urandom | od -An -tx1 | tr -d ' \n')"

SKILL_DIR="$PROJECT_ROOT/.humanize/skill/$UNIQUE_ID"
mkdir -p "$SKILL_DIR"

SANITIZED_PROJECT_PATH=$(echo "$PROJECT_ROOT" | sed 's/[^a-zA-Z0-9._-]/-/g' | sed 's/--*/-/g')
CACHE_BASE="${XDG_CACHE_HOME:-$HOME/.cache}"
CACHE_DIR="$CACHE_BASE/humanize/$SANITIZED_PROJECT_PATH/skill-$UNIQUE_ID"
if ! mkdir -p "$CACHE_DIR" 2>/dev/null; then
    CACHE_DIR="$SKILL_DIR/cache"
    mkdir -p "$CACHE_DIR"
    echo "ask-gpt-pro: warning: home cache not writable, using $CACHE_DIR" >&2
fi

# ========================================
# Build run_id (must match [A-Za-z0-9._-], max 100 chars)
# ========================================

# Canonical form: ask-<utc-timestamp>-<uuid-lower>
if command -v uuidgen &>/dev/null; then
    _uuid=$(uuidgen | tr '[:upper:]' '[:lower:]')
else
    _uuid=$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')
    _uuid="${_uuid:0:8}-${_uuid:8:4}-${_uuid:12:4}-${_uuid:16:4}-${_uuid:20:12}"
fi
RUN_ID="ask-$(date -u +%Y%m%dT%H%M%SZ)-$_uuid"

# ========================================
# Save Input
# ========================================

cat > "$SKILL_DIR/input.md" << EOF
# Ask GPT-Pro Input

## Question

$QUESTION

## Configuration

- Transport: $([ "$DIRECT_MODE" -eq 1 ] && echo "direct (on $SSH_HOST)" || echo "ssh ($SSH_HOST)")
- Timeout: ${ASK_TIMEOUT}s
- Run ID: $RUN_ID
- Timestamp: $TIMESTAMP
- Tool: gpt-pro
- Model: gpt-5-pro
EOF

# Write prompt to a file for gpt-pro-relay to read via stdin
PROMPT_FILE="$CACHE_DIR/prompt.md"
printf '%s\n' "$QUESTION" > "$PROMPT_FILE"

# ========================================
# Cache file paths (matched by monitor)
# ========================================

GPT_PRO_CMD_FILE="$CACHE_DIR/gpt-pro-run.cmd"
GPT_PRO_STDOUT_FILE="$CACHE_DIR/gpt-pro-run.out"
GPT_PRO_STDERR_FILE="$CACHE_DIR/gpt-pro-run.log"

{
    echo "# gpt-pro-relay ask-gpt-pro invocation debug info"
    echo "# Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "# Working directory: $PROJECT_ROOT"
    echo "# Transport: $([ "$DIRECT_MODE" -eq 1 ] && echo "direct" || echo "ssh $SSH_HOST")"
    echo "# Run ID: $RUN_ID"
    echo "# Wall-clock timeout: ${ASK_TIMEOUT}s"
    echo ""
    if (( DIRECT_MODE )); then
        echo "gpt-pro-relay ask --run-id \"$RUN_ID\" < <prompt>"
    else
        echo "ssh $SSH_HOST gpt-pro-relay ask --run-id \"$RUN_ID\" --no-wait < <prompt>"
        echo "ssh $SSH_HOST gpt-pro-relay fetch \"$RUN_ID\" --timeout 60   # polled until done"
    fi
    echo ""
    echo "# Prompt content:"
    cat "$PROMPT_FILE"
} > "$GPT_PRO_CMD_FILE"

# ========================================
# Run gpt-pro-relay
# ========================================

epoch_to_iso() {
    local epoch="$1"
    date -u -d "@$epoch" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
        || date -u -r "$epoch" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
        || echo "unknown"
}

write_metadata() {
    local exit_code="$1" duration="$2" status="$3" started="$4"
    cat > "$SKILL_DIR/metadata.md" << EOF
---
tool: gpt-pro
model: gpt-5-pro
run_id: $RUN_ID
transport: $([ "$DIRECT_MODE" -eq 1 ] && echo "direct" || echo "ssh:$SSH_HOST")
timeout: $ASK_TIMEOUT
exit_code: $exit_code
duration: ${duration}s
status: $status
started_at: $started
---
EOF
}

echo "ask-gpt-pro: run_id=$RUN_ID timeout=${ASK_TIMEOUT}s" >&2
echo "ask-gpt-pro: cache=$CACHE_DIR" >&2

START_TIME=$(date +%s)
START_ISO=$(epoch_to_iso "$START_TIME")

EXIT_CODE=0

if (( DIRECT_MODE )); then
    echo "ask-gpt-pro: invoking gpt-pro-relay directly on $SSH_HOST (timeout ${ASK_TIMEOUT}s)..." >&2
    if run_with_timeout "$ASK_TIMEOUT" gpt-pro-relay ask --run-id "$RUN_ID" \
            < "$PROMPT_FILE" \
            > "$GPT_PRO_STDOUT_FILE" \
            2> "$GPT_PRO_STDERR_FILE"; then
        :
    else
        EXIT_CODE=$?
    fi
else
    SSH_OPTS=(-S none -o BatchMode=yes -o ConnectTimeout=15 -o ServerAliveInterval=15 -o ServerAliveCountMax=4)

    echo "ask-gpt-pro: phase 1 - submitting via ssh $SSH_HOST..." >&2
    if ssh "${SSH_OPTS[@]}" "$SSH_HOST" gpt-pro-relay ask --run-id "$RUN_ID" --no-wait \
            < "$PROMPT_FILE" \
            2>> "$GPT_PRO_STDERR_FILE"; then
        :
    else
        EXIT_CODE=$?
        echo "ask-gpt-pro: phase 1 submit failed (rc=$EXIT_CODE)" >&2
        END_TIME=$(date +%s)
        write_metadata "$EXIT_CODE" "$((END_TIME - START_TIME))" "error" "$START_ISO"
        exit "$EXIT_CODE"
    fi

    echo "ask-gpt-pro: phase 2 - polling fetch (each session <=60s)..." >&2
    deadline=$((SECONDS + ASK_TIMEOUT))
    delay=5
    fetched=0
    while (( SECONDS < deadline )); do
        if out=$(ssh "${SSH_OPTS[@]}" "$SSH_HOST" gpt-pro-relay fetch "$RUN_ID" --timeout 60 \
                    2>> "$GPT_PRO_STDERR_FILE"); then
            printf '%s' "$out" > "$GPT_PRO_STDOUT_FILE"
            fetched=1
            break
        else
            rc=$?
            case $rc in
                124) delay=5 ;;                                # still pending; tight loop
                255) sleep "$delay"; (( delay < 30 )) && delay=$((delay * 2)) ;;  # ssh drop
                *)   EXIT_CODE=$rc; break ;;                   # terminal error
            esac
        fi
    done

    if (( ! fetched )) && (( EXIT_CODE == 0 )); then
        EXIT_CODE=124  # overall wall-clock timeout
        echo "ask-gpt-pro: overall timeout for run $RUN_ID" >&2
    fi
fi

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo "ask-gpt-pro: exit_code=$EXIT_CODE duration=${DURATION}s" >&2

# ========================================
# Handle Results
# ========================================

if [[ $EXIT_CODE -eq 124 ]]; then
    echo "Error: gpt-pro-relay timed out after ${ASK_TIMEOUT} seconds" >&2
    echo "  Run dir on $SSH_HOST: ~/.gpt-pro/runs/$RUN_ID/" >&2
    echo "  Recover with: ssh $SSH_HOST gpt-pro-relay fetch $RUN_ID --timeout 0" >&2
    write_metadata 124 "$DURATION" "timeout" "$START_ISO"
    exit 124
fi

if [[ $EXIT_CODE -ne 0 ]]; then
    echo "Error: gpt-pro-relay exited with code $EXIT_CODE" >&2
    if [[ -s "$GPT_PRO_STDERR_FILE" ]]; then
        echo "" >&2
        echo "gpt-pro-relay stderr (last 20 lines):" >&2
        tail -20 "$GPT_PRO_STDERR_FILE" >&2
    fi
    echo "" >&2
    echo "Debug logs: $CACHE_DIR" >&2
    write_metadata "$EXIT_CODE" "$DURATION" "error" "$START_ISO"
    exit "$EXIT_CODE"
fi

if [[ ! -s "$GPT_PRO_STDOUT_FILE" ]]; then
    echo "Error: gpt-pro-relay returned empty response" >&2
    if [[ -s "$GPT_PRO_STDERR_FILE" ]]; then
        echo "" >&2
        echo "gpt-pro-relay stderr (last 20 lines):" >&2
        tail -20 "$GPT_PRO_STDERR_FILE" >&2
    fi
    echo "" >&2
    echo "Debug logs: $CACHE_DIR" >&2
    write_metadata 0 "$DURATION" "empty_response" "$START_ISO"
    exit 1
fi

# ========================================
# Save Output and Metadata
# ========================================

cp "$GPT_PRO_STDOUT_FILE" "$SKILL_DIR/output.md"
write_metadata 0 "$DURATION" "success" "$START_ISO"

echo "ask-gpt-pro: response saved to $SKILL_DIR/output.md" >&2

# ========================================
# Output Response
# ========================================

cat "$GPT_PRO_STDOUT_FILE"
