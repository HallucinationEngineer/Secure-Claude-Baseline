#!/usr/bin/env bash
# PreCompact hook — snapshot the session transcript to an audit directory before
# context is compacted and detail is lost. Useful for post-hoc review / incident response.
set -euo pipefail

EVENT_JSON="$(cat)"

AUDIT_DIR="${CLAUDE_AUDIT_DIR:-.claude/audit}"
mkdir -p "$AUDIT_DIR"

TS="$(date -u +%Y%m%dT%H%M%SZ)"
SNAPSHOT_FILE="${AUDIT_DIR}/session-${TS}.json"

# The transcript path is supplied on the event in most Claude Code versions.
if command -v jq >/dev/null 2>&1; then
  TRANSCRIPT_PATH="$(printf '%s' "$EVENT_JSON" | jq -r '.transcript_path // empty')"
else
  TRANSCRIPT_PATH=""
fi

if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
  cp "$TRANSCRIPT_PATH" "$SNAPSHOT_FILE"
  echo "Session snapshot written to ${SNAPSHOT_FILE}" >&2
else
  printf '%s\n' "$EVENT_JSON" > "$SNAPSHOT_FILE"
  echo "Session event envelope written to ${SNAPSHOT_FILE} (transcript path unavailable)" >&2
fi

exit 0
