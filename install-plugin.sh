#!/usr/bin/env bash
# Link this repository's skills into an agent's skills directory.
#
# You do not need this to use the plugin: an agent working inside a clone of this
# repository already reads AGENTS.md and skills/. Run this only to make the skills
# available from any directory.
#
#   ./install-plugin.sh                      # detect the installed CLI
#   ./install-plugin.sh --engine both
#   ./install-plugin.sh --replace --copy
#   ./install-plugin.sh --check              # validate structure, install nothing
set -euo pipefail

REPO_ROOT=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
MODE=symlink
REPLACE=false
ENGINE=
CHECK=false
SKILLS=(
  tyk-deployment-planner
  tyk-deployment-runner
  tyk-production-readiness
)

usage() {
  cat <<'EOF'
Usage: ./install-plugin.sh [--engine codex|claude|both] [--copy] [--replace] [--check]

Installs the bundled Tyk deployment skills into the agent skills directory.

  --engine    Target agent: codex (CODEX_HOME), claude (CLAUDE_CONFIG_DIR), or both.
              Defaults to TYK_INSTALL_ENGINE, otherwise whichever CLI is installed.
  --copy      Copy each skill instead of creating symlinks.
  --replace   Preserve a differing installation as a timestamped backup.
  --check     Verify the plugin structure and exit without installing.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --engine)
      [[ $# -ge 2 ]] || { printf '%s\n' '--engine needs a value' >&2; exit 2; }
      ENGINE=$2; shift 2 ;;
    --copy) MODE=copy; shift ;;
    --replace) REPLACE=true; shift ;;
    --check) CHECK=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

check_structure() {
  local bad=0
  [[ -f "$REPO_ROOT/plugin.json" ]] || { printf 'missing plugin.json\n' >&2; bad=1; }
  for name in "${SKILLS[@]}"; do
    local dir="$REPO_ROOT/skills/$name"
    if [[ ! -f "$dir/SKILL.md" ]]; then
      printf 'missing skills/%s/SKILL.md\n' "$name" >&2; bad=1; continue
    fi
    # The frontmatter name must match the directory, or a client will skip it.
    local declared
    declared=$(sed -n '/^---$/,/^---$/p' "$dir/SKILL.md" | sed -n 's/^name:[[:space:]]*//p' | head -1)
    if [[ "$declared" != "$name" ]]; then
      printf 'skills/%s/SKILL.md declares name "%s"\n' "$name" "$declared" >&2; bad=1
    fi
  done
  for f in "$REPO_ROOT"/skills/*/scripts/*; do
    [[ -e "$f" ]] || continue
    [[ -x "$f" ]] || { printf 'not executable: %s\n' "${f#"$REPO_ROOT"/}" >&2; bad=1; }
  done
  if (( bad )); then
    printf '\nplugin structure check FAILED\n' >&2
    return 1
  fi
  printf 'plugin structure OK: %d skills\n' "${#SKILLS[@]}"
}

if [[ "$CHECK" == true ]]; then
  check_structure
  exit $?
fi
check_structure

resolve_engine() {
  local requested=${1:-}
  [[ -z "$requested" ]] && requested=${TYK_INSTALL_ENGINE:-}
  if [[ -n "$requested" ]]; then printf '%s' "$requested"; return 0; fi
  if command -v codex >/dev/null 2>&1; then printf 'codex'; return 0; fi
  if command -v claude >/dev/null 2>&1; then printf 'claude'; return 0; fi
  printf 'Neither the codex nor the claude CLI was found. Pass --engine explicitly.\n' >&2
  return 1
}

skills_root() {
  case "$1" in
    codex)  printf '%s/skills' "${CODEX_HOME:-$HOME/.codex}" ;;
    claude) printf '%s/skills' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" ;;
    *) printf 'Unknown engine: %s\n' "$1" >&2; return 1 ;;
  esac
}

ENGINES=()
if [[ "$ENGINE" == both ]]; then
  ENGINES=(codex claude)
else
  ENGINES=("$(resolve_engine "$ENGINE")")
fi

install_one() {
  local root=$1 name=$2
  local source="$REPO_ROOT/skills/$name"
  local target="$root/$name"
  local current backup

  if [[ -L "$target" ]]; then
    current=$(python3 -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).resolve())' "$target")
    if [[ "$current" == "$source" && "$MODE" == symlink ]]; then
      printf '  already linked: %s\n' "$target"; return 0
    fi
  fi

  if [[ -e "$target" || -L "$target" ]]; then
    if [[ -d "$target" && ! -L "$target" ]] && diff -qr "$source" "$target" >/dev/null 2>&1; then
      printf '  identical already installed: %s\n' "$target"; return 0
    fi
    if [[ "$REPLACE" != true ]]; then
      printf '  a different installation exists at %s\n' "$target" >&2
      printf '  re-run with --replace to keep it as a backup first\n' >&2
      return 1
    fi
    backup="${target}.backup.$(date -u +%Y%m%dT%H%M%SZ)"
    mv "$target" "$backup"
    printf '  preserved previous installation: %s\n' "$backup"
  fi

  if [[ "$MODE" == copy ]]; then
    cp -R "$source" "$target"; printf '  copied: %s\n' "$target"
  else
    ln -s "$source" "$target"; printf '  linked: %s\n' "$target"
  fi
}

status=0
for engine in "${ENGINES[@]}"; do
  root=$(skills_root "$engine")
  printf 'installing for %s: %s\n' "$engine" "$root"
  mkdir -p "$root"
  for skill in "${SKILLS[@]}"; do
    install_one "$root" "$skill" || status=1
  done
done
exit $status
