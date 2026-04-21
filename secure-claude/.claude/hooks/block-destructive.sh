#!/usr/bin/env bash
# PreToolUse hook for Bash — blocks obviously destructive or exfiltration-y commands.
# The deny list in settings.json is the primary guardrail; this script is a defense-in-depth net
# that catches obfuscated variants (e.g. "r""m -rf /", piping through base64 -d | sh, etc.).
#
# Break-glass: set CLAUDE_BREAKGLASS="<reason>" to allow ONE normally-blocked call.
# The bypass is audit-logged loudly via stderr and a sentinel file at
# .claude/audit/breakglass.log so it's impossible to use silently.
set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
# shellcheck source=lib/patterns.sh
. "${LIB_DIR}/patterns.sh"

EVENT_JSON="$(cat)"

if command -v jq >/dev/null 2>&1; then
  CMD="$(printf '%s' "$EVENT_JSON" | jq -r '.tool_input.command // empty')"
else
  CMD="$(printf '%s' "$EVENT_JSON" | grep -oE '"command"\s*:\s*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')"
fi

[ -z "$CMD" ] && exit 0

# Normalise whitespace + lowercase for pattern matching (but preserve original for messages)
NORM="$(printf '%s' "$CMD" | tr -s '[:space:]' ' ' | tr '[:upper:]' '[:lower:]')"

for p in "${DESTRUCTIVE_COMMAND_PATTERNS[@]}"; do
  if printf '%s' "$NORM" | grep -Eq "$p"; then

    # ---- Break-glass override -------------------------------------------
    REASON="${CLAUDE_BREAKGLASS:-}"
    if [ -n "$REASON" ]; then
      TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      AUDIT_DIR="${CLAUDE_AUDIT_DIR:-.claude/audit}"
      mkdir -p "$AUDIT_DIR" 2>/dev/null || true
      LOG="${AUDIT_DIR}/breakglass.log"

      {
        echo "=== BREAK-GLASS OVERRIDE ==="
        echo "ts     : ${TS}"
        echo "user   : ${USER:-unknown}"
        echo "pattern: ${p}"
        echo "reason : ${REASON}"
        echo "cmd    : ${CMD}"
        echo
      } | tee -a "$LOG" >&2

      exit 0
    fi

    # ---- Normal block ---------------------------------------------------
    echo "BLOCKED: command matches dangerous pattern /${p}/." >&2
    echo "Command: ${CMD}" >&2
    echo "If this is intentional, either:" >&2
    echo "  * run it outside the agent, OR" >&2
    echo "  * set CLAUDE_BREAKGLASS=\"<ticket or reason>\" for a ONE-shot, audit-logged bypass." >&2
    exit 2
  fi
done

exit 0
