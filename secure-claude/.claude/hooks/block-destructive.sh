#!/usr/bin/env bash
# PreToolUse hook for Bash — blocks obviously destructive or exfiltration-y commands.
# The deny list in settings.json is the primary guardrail; this script is a defense-in-depth net
# that catches obfuscated variants (e.g. "r""m -rf /", piping through base64 -d | sh, etc.).
set -euo pipefail

EVENT_JSON="$(cat)"

if command -v jq >/dev/null 2>&1; then
  CMD="$(printf '%s' "$EVENT_JSON" | jq -r '.tool_input.command // empty')"
else
  CMD="$(printf '%s' "$EVENT_JSON" | grep -oE '"command"\s*:\s*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')"
fi

[ -z "$CMD" ] && exit 0

# Normalise whitespace + lowercase for pattern matching (but preserve original for messages)
NORM="$(printf '%s' "$CMD" | tr -s '[:space:]' ' ' | tr '[:upper:]' '[:lower:]')"

DENY_PATTERNS=(
  'rm -rf /'
  'rm -rf \*'
  'rm -rf ~'
  'rm -rf \$home'
  ':(){ :\|:& };:'                  # fork bomb
  'dd if=.* of=/dev/'                # disk wipe
  'mkfs\.'                           # format filesystem
  '> /dev/sda'
  'chmod -r 777 /'
  'curl .* \| (ba)?sh'
  'wget .* \| (ba)?sh'
  'curl .* \| python'
  'base64 -d \| (ba)?sh'
  'eval "\$\(curl'
  'git push.*--force.*(main|master)'
  'git reset --hard origin/(main|master)'
  'history -c'
  'shred '
)

for p in "${DENY_PATTERNS[@]}"; do
  if printf '%s' "$NORM" | grep -Eq "$p"; then
    echo "BLOCKED: command matches dangerous pattern /${p}/." >&2
    echo "Command: ${CMD}" >&2
    echo "If this is intentional, run it outside the agent or update .claude/hooks/block-destructive.sh." >&2
    exit 2
  fi
done

exit 0
