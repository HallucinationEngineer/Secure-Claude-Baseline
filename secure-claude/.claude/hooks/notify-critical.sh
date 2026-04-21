#!/usr/bin/env bash
# Notification hook — forward critical tool-call events to Slack (or any webhook).
# Set SLACK_WEBHOOK_URL in .env / the environment. If unset, the hook is a no-op.
set -euo pipefail

EVENT_JSON="$(cat)"
WEBHOOK="${SLACK_WEBHOOK_URL:-}"

if [ -z "$WEBHOOK" ]; then
  exit 0
fi

if command -v jq >/dev/null 2>&1; then
  MESSAGE="$(printf '%s' "$EVENT_JSON" | jq -r '.message // "Claude Code notification"')"
  TITLE="$(printf '%s' "$EVENT_JSON" | jq -r '.title // "Claude Code"')"
else
  MESSAGE="Claude Code notification"
  TITLE="Claude Code"
fi

PAYLOAD="$(printf '{"text":"*%s*\\n%s"}' "$TITLE" "$MESSAGE")"

# Best-effort; do not fail the session on network issues.
curl -fsS -X POST -H 'Content-Type: application/json' --data "$PAYLOAD" "$WEBHOOK" >/dev/null 2>&1 || true

exit 0
