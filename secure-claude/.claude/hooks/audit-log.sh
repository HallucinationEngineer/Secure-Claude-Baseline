#!/usr/bin/env bash
# PostToolUse hook — emit an audit record for every tool call.
#
# Sinks (all independent, all controlled by env vars):
#
#   LOCAL (always on; at least one of):
#     CLAUDE_AUDIT_SINK=sqlite|jsonl|both|none     default: auto
#       auto  → sqlite if sqlite3 is on PATH, else jsonl
#       none  → skip local sink entirely (only makes sense with a remote sink)
#     CLAUDE_AUDIT_DIR=<path>                      default: .claude/audit
#
#   REMOTE (all optional, fire-and-forget):
#     CLAUDE_AUDIT_SUMO_URL=<Sumo HTTP Source URL>
#     CLAUDE_AUDIT_HTTP_URL=<generic HTTPS endpoint — Splunk HEC, Datadog, ELK, webhook>
#     CLAUDE_AUDIT_HTTP_AUTH=<full Authorization header value, e.g. "Splunk <token>" or "Bearer ...">
#
#   REDACTION:
#     CLAUDE_AUDIT_REDACT=1   strip secret-looking patterns from input_preview
#                             before the record leaves the box (default: 1)
#     CLAUDE_AUDIT_MAX_PREVIEW=2048   max bytes of input_preview to retain
#
# Local failures never break the session. Remote failures are silent by design
# so that an unreachable SIEM can't wedge the developer's agent.
set -uo pipefail

EVENT_JSON="$(cat)"

AUDIT_DIR="${CLAUDE_AUDIT_DIR:-.claude/audit}"
MAX_PREVIEW="${CLAUDE_AUDIT_MAX_PREVIEW:-2048}"
REDACT="${CLAUDE_AUDIT_REDACT:-1}"
SINK="${CLAUDE_AUDIT_SINK:-auto}"

mkdir -p "$AUDIT_DIR" 2>/dev/null || true

TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# ---- Redact secret-looking values before anything leaves the box ---------

redact() {
  # stdin → stdout, replacing any known-secret shapes with ***REDACTED***
  local s
  s="$(cat)"
  if [ "$REDACT" != "1" ]; then
    printf '%s' "$s"; return
  fi
  # We strip high-confidence secret *shapes* (AWS/GH/Slack/OpenAI/private-key)
  # and JSON-shape credential fields. We do NOT try to catch arbitrary
  # `password=xxx` in code strings — that's the PreToolUse secret-scan hook's
  # job, and over-aggressive regex corrupts JSON records.
  printf '%s' "$s" | perl -pe '
    s/AKIA[0-9A-Z]{16}/***REDACTED_AWS***/g;
    s/ASIA[0-9A-Z]{16}/***REDACTED_AWS_STS***/g;
    s/AIza[0-9A-Za-z_-]{35}/***REDACTED_GOOGLE***/g;
    s/ghp_[0-9A-Za-z]{36,}/***REDACTED_GH_PAT***/g;
    s/github_pat_[0-9A-Za-z_]{80,}/***REDACTED_GH_FINEGRAIN***/g;
    s/xox[baprs]-[0-9A-Za-z-]{10,}/***REDACTED_SLACK***/g;
    s/sk-[0-9A-Za-z]{32,}/***REDACTED_API_KEY***/g;
    s/-----BEGIN (RSA |OPENSSH |EC |PGP )?PRIVATE KEY-----[\s\S]*?-----END (RSA |OPENSSH |EC |PGP )?PRIVATE KEY-----/***REDACTED_PRIVATE_KEY***/g;
    s/"(password|passwd|secret|api[_-]?key|access[_-]?token|auth|bearer|token)"\s*:\s*"[^"]*"/"$1":"***REDACTED***"/gi;
  ' 2>/dev/null || printf '%s' "$s"   # if perl is missing, pass through
}

# ---- Build the normalised record -----------------------------------------
# Redact the raw event BEFORE jq so JSON-shape credential keys (password,
# api_key, etc.) are matched at the actual JSON level. Then re-apply the
# redactor to the final record to catch any token shapes in the serialized
# preview that jq may have re-escaped inside strings.

REDACTED_EVENT="$(printf '%s' "$EVENT_JSON" | redact)"

if command -v jq >/dev/null 2>&1; then
  RECORD_JSON="$(printf '%s' "$REDACTED_EVENT" \
    | jq -c --arg ts "$TS" --argjson maxprev "$MAX_PREVIEW" '
        . as $e
        | {
            ts: $ts,
            tool: ($e.tool_name // $e.hook_event_name // "unknown"),
            event: ($e.hook_event_name // ""),
            cwd: ($e.cwd // ""),
            session_id: ($e.session_id // ""),
            input_preview: (($e.tool_input // {}) | tostring | .[0:$maxprev]),
            blocked: ($e.permission_decision // "")
          }')"
else
  RECORD_JSON="$(printf '{"ts":"%s","raw":%s}' "$TS" "$REDACTED_EVENT")"
fi

REDACTED_RECORD="$(printf '%s' "$RECORD_JSON" | redact)"

# ---- Decide local sink ---------------------------------------------------

if [ "$SINK" = "auto" ]; then
  if command -v sqlite3 >/dev/null 2>&1; then
    SINK="sqlite"
  else
    SINK="jsonl"
  fi
fi

# ---- Local: SQLite -------------------------------------------------------

# SQL-escape a single string value: double any embedded single quotes.
sql_quote() {
  local v="$1"
  v="${v//\'/\'\'}"
  printf "'%s'" "$v"
}

write_sqlite() {
  local db="${AUDIT_DIR}/tool-calls.db"
  command -v sqlite3 >/dev/null 2>&1 || return 1
  command -v jq      >/dev/null 2>&1 || return 1

  sqlite3 "$db" <<'SQL' 2>/dev/null || return 1
CREATE TABLE IF NOT EXISTS tool_calls (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  ts            TEXT    NOT NULL,
  tool          TEXT,
  event         TEXT,
  cwd           TEXT,
  session_id    TEXT,
  blocked       TEXT,
  input_preview TEXT,
  raw           TEXT
);
CREATE INDEX IF NOT EXISTS idx_tc_ts      ON tool_calls(ts);
CREATE INDEX IF NOT EXISTS idx_tc_tool    ON tool_calls(tool);
CREATE INDEX IF NOT EXISTS idx_tc_session ON tool_calls(session_id);
CREATE INDEX IF NOT EXISTS idx_tc_blocked ON tool_calls(blocked);
SQL

  local ts tool event cwd session_id blocked input_preview
  ts="$(printf '%s' "$REDACTED_RECORD"            | jq -r '.ts // ""')"
  tool="$(printf '%s' "$REDACTED_RECORD"          | jq -r '.tool // ""')"
  event="$(printf '%s' "$REDACTED_RECORD"         | jq -r '.event // ""')"
  cwd="$(printf '%s' "$REDACTED_RECORD"           | jq -r '.cwd // ""')"
  session_id="$(printf '%s' "$REDACTED_RECORD"    | jq -r '.session_id // ""')"
  blocked="$(printf '%s' "$REDACTED_RECORD"       | jq -r '.blocked // ""')"
  input_preview="$(printf '%s' "$REDACTED_RECORD" | jq -r '.input_preview // ""')"

  local sql
  sql="INSERT INTO tool_calls (ts, tool, event, cwd, session_id, blocked, input_preview, raw) VALUES ($(sql_quote "$ts"), $(sql_quote "$tool"), $(sql_quote "$event"), $(sql_quote "$cwd"), $(sql_quote "$session_id"), $(sql_quote "$blocked"), $(sql_quote "$input_preview"), $(sql_quote "$REDACTED_RECORD"));"

  printf '%s\n' "$sql" | sqlite3 "$db" 2>/dev/null
}

write_jsonl() {
  printf '%s\n' "$REDACTED_RECORD" >> "${AUDIT_DIR}/tool-calls.jsonl"
}

case "$SINK" in
  sqlite) write_sqlite || write_jsonl ;;      # fall back if sqlite fails
  jsonl)  write_jsonl ;;
  both)   write_sqlite; write_jsonl ;;
  none)   : ;;
  *)      write_jsonl ;;
esac

# ---- Remote: fire-and-forget ---------------------------------------------
# We run curl in the background, detach it from the shell, and redirect all
# output so a slow/broken SIEM can never stall the agent.

post_remote() {
  local url="$1"; shift
  [ -z "$url" ] && return 0
  command -v curl >/dev/null 2>&1 || return 0

  local extra_headers=()
  if [ -n "${CLAUDE_AUDIT_HTTP_AUTH:-}" ] && [ "${2:-}" = "http" ]; then
    extra_headers=(-H "Authorization: ${CLAUDE_AUDIT_HTTP_AUTH}")
  fi

  (
    curl -fsS --max-time 5 \
      -X POST \
      -H "Content-Type: application/json" \
      "${extra_headers[@]}" \
      --data "$REDACTED_RECORD" \
      "$url" >/dev/null 2>&1
  ) </dev/null >/dev/null 2>&1 &
  disown 2>/dev/null || true
}

post_remote "${CLAUDE_AUDIT_SUMO_URL:-}" sumo
post_remote "${CLAUDE_AUDIT_HTTP_URL:-}" http

exit 0
