#!/usr/bin/env bash
# lint-plugin.sh — Plugin consistency checks for codex-collab
# Checks:
#   1. Version sync between plugin.json and marketplace.json
#   2. bash blocks in commands/*.md: syntax + CODEX_SKILL_CONTEXT marker
#   3. (warning-only) boilerplate drift in HELPERS loading chains
# Exit 0 on clean; non-zero on any error-level violation.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ERRORS=0
WARNINGS=0

# ─────────────────────────────────────────────
# Check 1: version sync
# ─────────────────────────────────────────────
check_version_sync() {
  local plugin_ver marketplace_ver
  plugin_ver="$(jq -r '.version' "$REPO_ROOT/.claude-plugin/plugin.json")"
  marketplace_ver="$(jq -r '.plugins[0].version' "$REPO_ROOT/.claude-plugin/marketplace.json")"

  if [ "$plugin_ver" = "$marketplace_ver" ]; then
    echo "[OK] Version sync: $plugin_ver"
  else
    echo "[ERROR] Version mismatch: plugin.json=$plugin_ver, marketplace.json=$marketplace_ver"
    ERRORS=$((ERRORS + 1))
  fi
}

# ─────────────────────────────────────────────
# Check 2: bash blocks in commands/*.md
# ─────────────────────────────────────────────
check_bash_blocks() {
  local tmpdir
  tmpdir="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmpdir'" EXIT

  local md_files=()
  for f in "$REPO_ROOT/commands/"*.md; do
    [ -f "$f" ] && md_files+=("$f")
  done

  if [ ${#md_files[@]} -eq 0 ]; then
    echo "[WARN] No commands/*.md files found"
    WARNINGS=$((WARNINGS + 1))
    return
  fi

  local total_blocks=0
  local syntax_errors=0
  local missing_marker=0

  for md_file in "${md_files[@]}"; do
    local fname
    fname="$(basename "$md_file")"
    local block_num=0
    local in_block=0
    local block_file=""

    # Extract bash blocks using awk; write each to a numbered temp file
    # We process line-by-line in a subshell to avoid nested bash issues
    while IFS= read -r line; do
      if [ "$in_block" -eq 0 ] && [ "$line" = '```bash' ]; then
        in_block=1
        block_num=$((block_num + 1))
        block_file="$tmpdir/${fname%.md}-block-$(printf '%03d' "$block_num").sh"
        : > "$block_file"
        continue
      fi
      if [ "$in_block" -eq 1 ] && [ "$line" = '```' ]; then
        in_block=0
        continue
      fi
      if [ "$in_block" -eq 1 ]; then
        printf '%s\n' "$line" >> "$block_file"
      fi
    done < "$md_file"

    local file_block_count="$block_num"
    total_blocks=$((total_blocks + file_block_count))

    # Validate each extracted block
    for bf in "$tmpdir/${fname%.md}-block-"*.sh; do
      [ -f "$bf" ] || continue
      local bname
      bname="$(basename "$bf")"
      local bnum="${bname##*-block-}"
      bnum="${bnum%.sh}"
      # Remove leading zeros for display
      local bnum_display
      bnum_display="$(printf '%d' "$((10#$bnum))")"

      # Syntax check
      if ! bash -n "$bf" 2>"$tmpdir/bash-err"; then
        local err_msg
        err_msg="$(cat "$tmpdir/bash-err")"
        echo "[ERROR] Syntax error in $fname block $bnum_display: $err_msg"
        ERRORS=$((ERRORS + 1))
        syntax_errors=$((syntax_errors + 1))
        continue
      fi

      # Marker check
      if ! grep -q 'CODEX_SKILL_CONTEXT=1' "$bf"; then
        echo "[ERROR] Missing CODEX_SKILL_CONTEXT marker in $fname block $bnum_display"
        ERRORS=$((ERRORS + 1))
        missing_marker=$((missing_marker + 1))
      fi
    done
  done

  echo "[OK] bash blocks checked: total=$total_blocks, syntax_errors=$syntax_errors, missing_marker=$missing_marker"
}

# ─────────────────────────────────────────────
# Check 3: boilerplate drift (warning only)
# ─────────────────────────────────────────────
# Canonical HELPERS loading chain (from CLAUDE.md):
#   HELPERS=""
#   if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh" ]; then
#     HELPERS="${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh"
#   elif [ -d ~/.claude/plugins/cache/codex-collab ]; then
#     HELPERS=$(ls -td ~/.claude/plugins/cache/codex-collab/codex-collab/*/scripts/codex-helpers.sh ...)
#   fi
#   [ -z "$HELPERS" ] || [ ! -f "$HELPERS" ] && HELPERS="$(pwd)/scripts/codex-helpers.sh"
#   [ -f "$HELPERS" ] && source "$HELPERS"
#
# Non-canonical (short-form) variant: skips the cache lookup entirely —
#   HELPERS="${CLAUDE_PLUGIN_ROOT:-$(pwd)}/scripts/codex-helpers.sh"
# This is the only form flagged as drift; the closing one-liner fallback is acceptable per CLAUDE.md.
check_boilerplate_drift() {
  local drift_found=0

  for md_file in "$REPO_ROOT/commands/"*.md; do
    [ -f "$md_file" ] || continue
    local fname
    fname="$(basename "$md_file")"

    # Count canonical chains (those with the full cache-lookup elif)
    # grep -c exits 1 on zero matches; || true prevents set -e from aborting
    local canonical
    canonical="$(grep -c 'plugins/cache/codex-collab/codex-collab' "$md_file" 2>/dev/null || true)"
    local short_form
    # SC2016: single quotes intentional — searching for literal text containing $(pwd)
    # shellcheck disable=SC2016
    short_form="$(grep -c 'CLAUDE_PLUGIN_ROOT:-\$(pwd)' "$md_file" 2>/dev/null || true)"

    if [ "$short_form" -gt 0 ]; then
      echo "[WARN] Boilerplate drift in $fname: canonical=$canonical, short-form=${short_form} (missing cache-lookup elif)"
      WARNINGS=$((WARNINGS + 1))
      drift_found=$((drift_found + 1))
    fi
  done

  if [ "$drift_found" -eq 0 ]; then
    echo "[OK] Boilerplate: no drift variants found"
  fi
}

# ─────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────
main() {
  echo "=== codex-collab plugin consistency lint ==="
  echo ""

  echo "-- Check 1: Version sync --"
  check_version_sync
  echo ""

  echo "-- Check 2: bash blocks (syntax + CODEX_SKILL_CONTEXT marker) --"
  check_bash_blocks
  echo ""

  echo "-- Check 3: boilerplate drift (warning only) --"
  check_boilerplate_drift
  echo ""

  echo "=== Summary: errors=$ERRORS, warnings=$WARNINGS ==="

  if [ "$ERRORS" -gt 0 ]; then
    echo "FAIL: $ERRORS error(s) found."
    exit 1
  else
    echo "PASS"
    exit 0
  fi
}

main "$@"
