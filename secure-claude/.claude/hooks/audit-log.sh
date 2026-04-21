#!/usr/bin/env bash
# PostToolUse hook — append an audit record for every tool call.
# One JSON line per event. Rotate externally (logrotate, ship to SIEM, etc.).
set -euo pipefail

EVENT_JSON="$(cat)"

AUDIT_DIR="${CLAUDE_AUDIT_DIR:-.claude/audit}"
mkdir -p "$AUDIT_DIR"

LOG_FILE="${AUDIT_DIR}/tool-calls.jsonl"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Normalise to a single line; redact content fields longer than 2 KB.
if command -v jq >/dev/null 2>&1; then
  printf '%s' "$EVENT_JSON" \
    | jq -c --arg ts "$TS" '
        . as $e
        | {
            ts: $ts,
            tool: ($e.tool_name // $e.hook_event_name // "unknown"),
            cwd: ($e.cwd // empty),
            session_id: ($e.session_id // empty),
            input_preview: (($e.tool_input // {}) | tostring | .[0:2048]),
            blocked: ($e.permission_decision // empty)
          }' \
    >> "$LOG_FILE"
else
  printf '{"ts":"%s","raw":%s}\n' "$TS" "$EVENT_JSON" >> "$LOG_FILE"
fi

exit 0
