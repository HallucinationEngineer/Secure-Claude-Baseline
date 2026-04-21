#!/usr/bin/env bash
# PostToolUse hook — run fast linters & type checks after Write/Edit/MultiEdit.
# Designed to be idempotent and non-fatal: linter failures surface as stderr warnings
# (Claude sees them and can self-correct) but do not block the session.
set -uo pipefail

EVENT_JSON="$(cat)"
if command -v jq >/dev/null 2>&1; then
  FILE_PATH="$(printf '%s' "$EVENT_JSON" | jq -r '.tool_input.file_path // empty')"
else
  FILE_PATH="$(printf '%s' "$EVENT_JSON" | grep -oE '"file_path"\s*:\s*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')"
fi

[ -z "$FILE_PATH" ] && exit 0
[ ! -f "$FILE_PATH" ] && exit 0

case "$FILE_PATH" in
  *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs)
    if [ -f "package.json" ] && command -v npx >/dev/null 2>&1; then
      npx --no-install eslint --max-warnings=0 "$FILE_PATH" 2>&1 || true
      npx --no-install tsc --noEmit 2>&1 | grep -F "$FILE_PATH" || true
    fi
    ;;
  *.py)
    command -v ruff >/dev/null 2>&1 && ruff check "$FILE_PATH" 2>&1 || true
    command -v mypy >/dev/null 2>&1 && mypy "$FILE_PATH" 2>&1 || true
    ;;
  *.go)
    command -v gofmt >/dev/null 2>&1 && gofmt -l "$FILE_PATH" 2>&1 || true
    command -v go >/dev/null 2>&1 && go vet "./..." 2>&1 || true
    ;;
  *.rs)
    command -v cargo >/dev/null 2>&1 && cargo clippy --quiet -- -D warnings 2>&1 || true
    ;;
  *.sh|*.bash)
    command -v shellcheck >/dev/null 2>&1 && shellcheck "$FILE_PATH" 2>&1 || true
    ;;
esac

exit 0
