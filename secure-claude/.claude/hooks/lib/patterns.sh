#!/usr/bin/env bash
# .claude/hooks/lib/patterns.sh
# Shared regex library sourced by secret-scan.sh, audit-log.sh, and
# block-destructive.sh. Keep additions in ONE place — every consumer picks
# them up automatically.
#
# Convention:
#   *_PATTERNS      : bash arrays of ERE regex, suitable for `grep -E`.
#   PERL_REDACTION  : a perl -pe script body, multiline, safe for use inside
#                     `perl -pe "$PERL_REDACTION"`.
#
# This file is POSIX-safe sourcing — no side effects, no exits.
#
# Every variable below is consumed by a sourcing script, so shellcheck's
# "appears unused" warning (SC2034) is a false positive for this file.
# shellcheck disable=SC2034

# ---- Secret shapes (grep -E form) ----------------------------------------
# Used by secret-scan.sh's regex fallback when gitleaks isn't installed.

SECRET_TOKEN_PATTERNS=(
  'AKIA[0-9A-Z]{16}'                                  # AWS access key id
  'ASIA[0-9A-Z]{16}'                                  # AWS STS
  'AIza[0-9A-Za-z_-]{35}'                             # Google API key
  'ghp_[0-9A-Za-z]{36,}'                              # GitHub PAT (classic)
  'github_pat_[0-9A-Za-z_]{80,}'                      # GitHub fine-grained PAT
  'xox[baprs]-[0-9A-Za-z-]{10,}'                      # Slack token
  'sk-[0-9A-Za-z]{32,}'                               # OpenAI / Anthropic-style
  '-----BEGIN (RSA |OPENSSH |EC |PGP )?PRIVATE KEY-----'
)

# ---- Destructive command shapes (grep -E, case-insensitive) --------------
# Used by block-destructive.sh. The permissions.deny list in settings.json
# is the primary guardrail; this is defense-in-depth for obfuscated variants.

DESTRUCTIVE_COMMAND_PATTERNS=(
  'rm -rf /'
  'rm -rf \*'
  'rm -rf ~'
  'rm -rf \$home'
  ':(){ :\|:& };:'                                    # fork bomb
  'dd if=.* of=/dev/'                                 # disk wipe
  'mkfs\.'                                            # format filesystem
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

# ---- Redaction rules (perl -pe body) -------------------------------------
# Used by audit-log.sh to strip secret shapes before records hit disk or
# leave the box. High-confidence shapes only; we deliberately do NOT try to
# catch arbitrary `password=xxx` in code strings — that would corrupt the
# JSON record and is the PreToolUse secret-scan hook's job anyway.
#
# WARNING: PERL_REDACTION is ONLY safe when passed to `perl -pe` (or -ne,
# -e with slurp). It contains embedded `$1` backrefs, multiline quantifiers,
# and unescaped double quotes that would break `sed`, `awk`, bash parameter
# expansion, or any language that isn't perl. If you need the same logic
# somewhere else, re-express it in that language — do NOT interpolate this
# string.

read -r -d '' PERL_REDACTION <<'PERL' || true
s/AKIA[0-9A-Z]{16}/***REDACTED_AWS***/g;
s/ASIA[0-9A-Z]{16}/***REDACTED_AWS_STS***/g;
s/AIza[0-9A-Za-z_-]{35}/***REDACTED_GOOGLE***/g;
s/ghp_[0-9A-Za-z]{36,}/***REDACTED_GH_PAT***/g;
s/github_pat_[0-9A-Za-z_]{80,}/***REDACTED_GH_FINEGRAIN***/g;
s/xox[baprs]-[0-9A-Za-z-]{10,}/***REDACTED_SLACK***/g;
s/sk-[0-9A-Za-z]{32,}/***REDACTED_API_KEY***/g;
s/-----BEGIN (RSA |OPENSSH |EC |PGP )?PRIVATE KEY-----[\s\S]*?-----END (RSA |OPENSSH |EC |PGP )?PRIVATE KEY-----/***REDACTED_PRIVATE_KEY***/g;
s/"(password|passwd|secret|api[_-]?key|access[_-]?token|auth|bearer|token)"\s*:\s*"[^"]*"/"$1":"***REDACTED***"/gi;
PERL

# ---- Prompt-injection shapes (grep -E, case-insensitive) -----------------
# Used by prompt-injection-scan.sh. Looks for content that is trying to
# hijack the agent when it gets read into context.

PROMPT_INJECTION_PATTERNS=(
  'ignore (all |the )?(previous|prior|above) (instructions|prompts|rules)'
  'disregard (all |the )?(previous|prior|above)'
  'forget (all |the )?(previous|prior|above)'
  'you are (now |an? new )?'
  'new (system |core )?instructions'
  '<\|?(system|im_start|im_end)\|?>'                  # chat-markup smuggling
  '\[\[?(system|user|assistant)\]\]?'                 # bracket-role smuggling
  '<(tool_use|invoke|function_calls)>'                # tool-call smuggling
  'override.*safety'
  'bypass.*(filter|restriction|guardrail)'
  'reveal.*(system prompt|hidden instructions)'
  'print (your|the) (system )?prompt'
)

# Unicode-tag-block smuggling range: U+E0000..U+E007F.
# Can't easily be expressed as a grep ERE; consumers detect via perl.
UNICODE_TAG_BLOCK_PERL='/[\x{E0000}-\x{E007F}]/'
