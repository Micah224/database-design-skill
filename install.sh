#!/usr/bin/env bash
# Install the database-design-discovery skill for one or more AI coding tools.
#
#   ./install.sh                # detect installed tools and install for each
#   ./install.sh claude codex   # install for the named tools only
#   ./install.sh --to <dir>     # copy the skill folder to an arbitrary skills directory
#   ./install.sh --link ...     # symlink instead of copy (keeps the skill in sync with this checkout)
#
# The skill is a plain folder (SKILL.md + scripts/ + references/ + assets/) in the
# open Agent Skills format, so "installing" is copying that folder into the place
# your tool looks for skills. Paths below reflect the tools as of September 2026;
# if yours differs, use --to. Every tool also reads AGENTS.md at a repo root, so
# vendoring this repository into a project works everywhere without installing.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$HERE/skills/database-design-discovery"
NAME="database-design-discovery"
MODE="copy"; TARGETS=(); TO=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --link) MODE="link"; shift ;;
    --to) TO="$2"; shift 2 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) TARGETS+=("$1"); shift ;;
  esac
done

place() {  # place <dest-dir>
  local dest="$1"
  mkdir -p "$(dirname "$dest")"
  rm -rf "$dest"
  if [[ "$MODE" == "link" ]]; then ln -s "$SRC" "$dest"; else cp -R "$SRC" "$dest"; fi
  echo "  ✓ $dest"
}

if [[ -n "$TO" ]]; then place "$TO/$NAME"; exit 0; fi

declare -A PATHS=(
  [claude]="$HOME/.claude/skills/$NAME"        # Claude Code / Claude Desktop (Cowork)
  [codex]="$HOME/.codex/skills/$NAME"          # OpenAI Codex CLI (user scope)
  [agents]="$HOME/.agents/skills/$NAME"        # cross-tool location used by several agents
  [copilot]="$HOME/.copilot/skills/$NAME"      # GitHub Copilot CLI / VS Code agent mode
  [gemini]="$HOME/.gemini/skills/$NAME"        # Gemini CLI
  [cursor]="$HOME/.cursor/skills/$NAME"        # Cursor
)
declare -A DETECT=(
  [claude]="$HOME/.claude" [codex]="$HOME/.codex" [agents]="$HOME/.agents"
  [copilot]="$HOME/.copilot" [gemini]="$HOME/.gemini" [cursor]="$HOME/.cursor"
)

if [[ ${#TARGETS[@]} -eq 0 ]]; then
  for t in claude codex agents copilot gemini cursor; do
    [[ -d "${DETECT[$t]}" ]] && TARGETS+=("$t")
  done
  if [[ ${#TARGETS[@]} -eq 0 ]]; then
    echo "No tool directories found under \$HOME. Use: $0 --to <your-skills-dir>"; exit 1
  fi
  echo "Detected: ${TARGETS[*]}"
fi

for t in "${TARGETS[@]}"; do
  if [[ -z "${PATHS[$t]:-}" ]]; then echo "  ✗ unknown tool '$t' (known: ${!PATHS[*]})"; continue; fi
  place "${PATHS[$t]}"
done
echo
echo "Project-scoped alternative: copy skills/ (and AGENTS.md) into any repository;"
echo "Claude Code reads .claude/skills/, Codex .codex/skills/ or .agents/skills/, Copilot .github/skills/."
