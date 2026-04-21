#!/usr/bin/env bash
# Secure Claude Baseline — installer.
# Copies secure-claude/.claude (and supporting files) into either a target project (local)
# or the user's home (~/.claude, global).
#
# Usage:
#   ./bootstrap.sh                         # interactive
#   ./bootstrap.sh --local [TARGET_DIR]    # install into TARGET_DIR (default: current working dir)
#   ./bootstrap.sh --global                # install into ~/.claude
#   ./bootstrap.sh --help
#
# Flags:
#   --dry-run   print actions, change nothing
#   --force     overwrite existing files without prompting (still skips .env)
#   --no-merge  skip JSON/gitignore merging and copy straight over (implies --force)
#
set -euo pipefail

# ---- Resolve paths ---------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="${SCRIPT_DIR}/secure-claude"

if [ ! -d "$SOURCE_DIR" ]; then
  echo "error: ${SOURCE_DIR} not found. Run bootstrap.sh from the Secure-Claude-Baseline repo root." >&2
  exit 1
fi

# ---- Arg parsing -----------------------------------------------------------

MODE=""
TARGET=""
DRY_RUN=0
FORCE=0
MERGE=1

print_help() {
  sed -n '2,20p' "$0"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --local)
      MODE="local"
      shift
      if [ "$#" -gt 0 ] && [ "${1:0:2}" != "--" ]; then
        TARGET="$1"; shift
      fi
      ;;
    --global)
      MODE="global"; shift
      ;;
    --dry-run)
      DRY_RUN=1; shift
      ;;
    --force)
      FORCE=1; shift
      ;;
    --no-merge)
      MERGE=0; FORCE=1; shift
      ;;
    -h|--help)
      print_help; exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      print_help
      exit 2
      ;;
  esac
done

# ---- Interactive mode ------------------------------------------------------

if [ -z "$MODE" ]; then
  echo "Secure Claude Baseline — installer"
  echo
  echo "Where would you like to install?"
  echo "  1) Local   — into a single project's .claude/ (recommended)"
  echo "  2) Global  — into ~/.claude/ (applies to every project without a local .claude/)"
  echo
  read -r -p "Choice [1/2]: " CHOICE
  case "$CHOICE" in
    1) MODE="local" ;;
    2) MODE="global" ;;
    *) echo "invalid choice"; exit 2 ;;
  esac
fi

if [ "$MODE" = "local" ] && [ -z "$TARGET" ]; then
  read -r -p "Target project directory [${PWD}]: " TARGET
  TARGET="${TARGET:-$PWD}"
fi

# ---- Resolve final destination --------------------------------------------

case "$MODE" in
  local)
    TARGET="$(cd "$TARGET" 2>/dev/null && pwd || echo "")"
    if [ -z "$TARGET" ] || [ ! -d "$TARGET" ]; then
      echo "error: target directory does not exist" >&2
      exit 1
    fi
    DEST_CLAUDE="${TARGET}/.claude"
    ;;
  global)
    DEST_CLAUDE="${HOME}/.claude"
    TARGET="$HOME"
    ;;
  *)
    echo "error: mode must be --local or --global" >&2
    exit 2
    ;;
esac

# ---- Logging helpers ------------------------------------------------------

log()  { printf '  %s\n' "$*"; }
act()  {
  if [ "$DRY_RUN" -eq 1 ]; then printf '  [dry-run] %s\n' "$*"; return 0; fi
  eval "$@"
}

confirm_overwrite() {
  local path="$1"
  if [ "$FORCE" -eq 1 ] || [ ! -e "$path" ]; then
    return 0
  fi
  read -r -p "  ${path} exists. Overwrite? [y/N] " answer
  [ "${answer:-N}" = "y" ] || [ "${answer:-N}" = "Y" ]
}

# ---- Plan summary ---------------------------------------------------------

echo
echo "Plan:"
echo "  mode     : $MODE"
echo "  target   : $TARGET"
echo "  dest     : $DEST_CLAUDE"
echo "  dry-run  : $([ $DRY_RUN -eq 1 ] && echo yes || echo no)"
echo "  force    : $([ $FORCE  -eq 1 ] && echo yes || echo no)"
echo "  merge    : $([ $MERGE  -eq 1 ] && echo yes || echo no)"
echo
if [ "$DRY_RUN" -eq 0 ] && [ "$FORCE" -eq 0 ]; then
  read -r -p "Proceed? [y/N] " CONFIRM
  if [ "${CONFIRM:-N}" != "y" ] && [ "${CONFIRM:-N}" != "Y" ]; then
    echo "aborted."
    exit 0
  fi
fi

# ---- Install the .claude/ tree --------------------------------------------

install_claude_tree() {
  local src="${SOURCE_DIR}/.claude"
  local dest="$DEST_CLAUDE"

  act "mkdir -p \"$dest\""

  # settings.json — merge if one already exists
  if [ -f "${dest}/settings.json" ] && [ "$MERGE" -eq 1 ] && [ "$FORCE" -eq 0 ]; then
    log "settings.json exists — merging (requires jq)"
    if command -v jq >/dev/null 2>&1; then
      if [ "$DRY_RUN" -eq 0 ]; then
        local tmp; tmp="$(mktemp)"
        jq -s '.[0] * .[1]' "${dest}/settings.json" "${src}/settings.json" > "$tmp"
        cp "$tmp" "${dest}/settings.json"
        rm -f "$tmp"
      else
        log "[dry-run] jq -s '.[0] * .[1]' existing baseline > settings.json"
      fi
    else
      log "  jq missing — falling back to side-by-side copy at settings.json.baseline.json"
      act "cp \"${src}/settings.json\" \"${dest}/settings.json.baseline.json\""
    fi
  else
    if confirm_overwrite "${dest}/settings.json"; then
      act "cp \"${src}/settings.json\" \"${dest}/settings.json\""
    fi
  fi

  # Everything else — straightforward copy (with overwrite prompts)
  for sub in commands skills agents hooks plugins; do
    if [ -d "${src}/${sub}" ]; then
      act "mkdir -p \"${dest}/${sub}\""
      if [ "$DRY_RUN" -eq 0 ]; then
        # -n = no-clobber unless --force
        if [ "$FORCE" -eq 1 ]; then
          cp -R "${src}/${sub}/." "${dest}/${sub}/"
        else
          cp -Rn "${src}/${sub}/." "${dest}/${sub}/"
        fi
      else
        log "[dry-run] cp -R${FORCE:+ (force)} ${src}/${sub}/. ${dest}/${sub}/"
      fi
    fi
  done

  # settings.local.json.example
  if [ -f "${src}/settings.local.json.example" ]; then
    act "cp \"${src}/settings.local.json.example\" \"${dest}/settings.local.json.example\""
  fi

  # Make hooks executable
  if [ -d "${dest}/hooks" ]; then
    act "chmod +x \"${dest}/hooks/\"*.sh 2>/dev/null || true"
  fi
}

# ---- Install project-level supporting files (local mode only) -------------

install_project_files() {
  local dest="$TARGET"

  # CLAUDE.md — merge by appending if one already exists
  if [ -f "${dest}/CLAUDE.md" ] && [ "$FORCE" -eq 0 ]; then
    log "CLAUDE.md exists — appending baseline section (idempotent)"
    if [ "$DRY_RUN" -eq 0 ]; then
      if ! grep -q "Secure Claude Baseline" "${dest}/CLAUDE.md" 2>/dev/null; then
        {
          echo
          echo "<!-- ==== Secure Claude Baseline (from secure-claude/CLAUDE.md) ==== -->"
          cat "${SOURCE_DIR}/CLAUDE.md"
        } >> "${dest}/CLAUDE.md"
      else
        log "  baseline section already present — skipping"
      fi
    fi
  else
    if confirm_overwrite "${dest}/CLAUDE.md"; then
      act "cp \"${SOURCE_DIR}/CLAUDE.md\" \"${dest}/CLAUDE.md\""
    fi
  fi

  # .mcp.json
  if confirm_overwrite "${dest}/.mcp.json"; then
    act "cp \"${SOURCE_DIR}/.mcp.json\" \"${dest}/.mcp.json\""
  fi

  # .env.example — merge by appending missing keys
  if [ -f "${dest}/.env.example" ] && [ "$FORCE" -eq 0 ]; then
    log ".env.example exists — appending any missing baseline keys"
    if [ "$DRY_RUN" -eq 0 ]; then
      while IFS= read -r line; do
        # Skip comments / blanks
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$line" ]] && continue
        local key="${line%%=*}"
        if ! grep -qE "^[[:space:]]*${key}=" "${dest}/.env.example"; then
          printf '%s\n' "$line" >> "${dest}/.env.example"
        fi
      done < "${SOURCE_DIR}/.env.example"
    fi
  else
    if confirm_overwrite "${dest}/.env.example"; then
      act "cp \"${SOURCE_DIR}/.env.example\" \"${dest}/.env.example\""
    fi
  fi

  # .gitignore — append missing entries
  local gi_dest="${dest}/.gitignore"
  if [ -f "$gi_dest" ] && [ "$FORCE" -eq 0 ]; then
    log ".gitignore exists — appending any missing baseline entries"
    if [ "$DRY_RUN" -eq 0 ]; then
      while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$line" ]] && continue
        if ! grep -qxF "$line" "$gi_dest"; then
          printf '%s\n' "$line" >> "$gi_dest"
        fi
      done < "${SOURCE_DIR}/.gitignore"
    fi
  else
    if confirm_overwrite "$gi_dest"; then
      act "cp \"${SOURCE_DIR}/.gitignore\" \"$gi_dest\""
    fi
  fi
}

# ---- Go --------------------------------------------------------------------

echo
echo "Installing .claude/ tree into ${DEST_CLAUDE}..."
install_claude_tree

if [ "$MODE" = "local" ]; then
  echo
  echo "Installing project files into ${TARGET}..."
  install_project_files
else
  echo
  echo "Global mode: skipping CLAUDE.md / .mcp.json / .env.example / .gitignore (those are per-project)."
fi

# ---- Done ------------------------------------------------------------------

echo
echo "Done$([ $DRY_RUN -eq 1 ] && echo " (dry-run — no files changed)" || echo "")."
echo
echo "Next steps:"
if [ "$MODE" = "local" ]; then
  echo "  1. cd \"${TARGET}\" && cp .env.example .env      # fill in real values"
  echo "  2. Install gitleaks so the PreToolUse hook has teeth:"
  echo "       brew install gitleaks   # or: go install github.com/gitleaks/gitleaks/v8@latest"
  echo "  3. Review .claude/settings.json allow/deny lists and tighten for your project."
  echo "  4. Open the project in Claude Code and run  /security-review  on your next diff."
else
  echo "  1. Install gitleaks so the PreToolUse hook has teeth:"
  echo "       brew install gitleaks   # or: go install github.com/gitleaks/gitleaks/v8@latest"
  echo "  2. Review ~/.claude/settings.json allow/deny lists."
  echo "  3. Per-project: drop a local .claude/ into each repo if you want project-specific rules."
  echo "     (Local settings merge on top of these global defaults.)"
fi
echo
echo "Credit: baseline designed by Okan Yildiz — https://www.linkedin.com/in/yildizokan"
