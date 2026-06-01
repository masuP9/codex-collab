#!/usr/bin/env bash
# Read-only Claude Code consultation helpers for Codex.

if [ -n "${_CLAUDE_COLLAB_HELPERS_LOADED:-}" ]; then
  return 0 2>/dev/null || exit 0
fi
_CLAUDE_COLLAB_HELPERS_LOADED=1

if [ -z "${CLAUDE_COLLAB_PROJECT_DIR:-}" ]; then
  if command -v git >/dev/null 2>&1 && git rev-parse --show-toplevel >/dev/null 2>&1; then
    CLAUDE_COLLAB_PROJECT_DIR="$(git rev-parse --show-toplevel)"
  else
    CLAUDE_COLLAB_PROJECT_DIR="$(pwd)"
  fi
fi
: "${CLAUDE_COLLAB_TMP_DIR:=${CLAUDE_COLLAB_PROJECT_DIR}/tmp}"
: "${CLAUDE_COLLAB_TIMEOUT:=600}"
: "${CLAUDE_COLLAB_REVIEW_TIMEOUT:=900}"

claude_tmp_dir() {
  local tmp_dir
  if [[ "$CLAUDE_COLLAB_TMP_DIR" = /* ]]; then
    tmp_dir="$CLAUDE_COLLAB_TMP_DIR"
  else
    tmp_dir="$(pwd)/${CLAUDE_COLLAB_TMP_DIR#./}"
  fi
  mkdir -p "$tmp_dir"
  printf '%s\n' "$tmp_dir"
}

claude_tmp_path() {
  local filename="$1"
  printf '%s/%s\n' "$(claude_tmp_dir)" "$filename"
}

claude_write_prompt() {
  local content="$1"
  local prefix="${2:-prompt}"
  local tmp_dir
  local prompt_file
  tmp_dir="$(claude_tmp_dir)"
  prompt_file="$(mktemp "${tmp_dir}/claude-${prefix}-XXXXXX")"
  printf '%s' "$content" > "$prompt_file"
  printf '%s\n' "$prompt_file"
}

claude_run_print() {
  local prompt_file="$1"
  local output_file="${2:-$(claude_tmp_path "claude-output-$$.md")}"
  local model="${3:-}"
  # Use the unset-only default: Claude CLI documents --tools "" as disabling all tools.
  local tools="${4-Read,Glob,Grep}"
  local wait_timeout="${5:-$CLAUDE_COLLAB_TIMEOUT}"
  local run_cwd="${6:-}"
  local effort="${7:-}"
  local append_system_prompt="${8:-}"
  local -a claude_args
  local -a runner
  local exit_code=0

  if [ ! -f "$prompt_file" ]; then
    printf 'Error: prompt file not found: %s\n' "$prompt_file" >&2
    return 1
  fi

  if ! command -v claude >/dev/null 2>&1; then
    printf 'Error: claude command not found\n' >&2
    return 1
  fi

  claude_args=(
    -p
    --disable-slash-commands
    --permission-mode plan
    --tools "$tools"
    --no-session-persistence
  )
  if [ -n "$model" ]; then
    claude_args+=(--model "$model")
  fi
  if [ -n "$effort" ]; then
    claude_args+=(--effort "$effort")
  fi
  if [ -n "$append_system_prompt" ]; then
    claude_args+=(--append-system-prompt "$append_system_prompt")
  fi

  runner=()
  if command -v timeout >/dev/null 2>&1; then
    runner=(timeout "$wait_timeout")
  elif command -v gtimeout >/dev/null 2>&1; then
    runner=(gtimeout "$wait_timeout")
  else
    printf 'Warning: timeout command not found; claude consultation has no time limit\n' >&2
  fi

  if [ -n "$run_cwd" ] && [ ! -d "$run_cwd" ]; then
    printf 'Error: claude working directory not found: %s\n' "$run_cwd" >&2
    return 1
  fi

  if [ "${#runner[@]}" -gt 0 ] && [ -n "$run_cwd" ]; then
    (set -o pipefail; cd "$run_cwd" && "${runner[@]}" claude "${claude_args[@]}" < "$prompt_file" | tee "$output_file") || exit_code=$?
  elif [ "${#runner[@]}" -gt 0 ]; then
    (set -o pipefail; "${runner[@]}" claude "${claude_args[@]}" < "$prompt_file" | tee "$output_file") || exit_code=$?
  elif [ -n "$run_cwd" ]; then
    (set -o pipefail; cd "$run_cwd" && claude "${claude_args[@]}" < "$prompt_file" | tee "$output_file") || exit_code=$?
  else
    (set -o pipefail; claude "${claude_args[@]}" < "$prompt_file" | tee "$output_file") || exit_code=$?
  fi
  if [ "$exit_code" -eq 124 ]; then
    printf 'Error: claude consultation timed out after %s seconds\n' "$wait_timeout" >&2
  fi
  return "$exit_code"
}

# Run a review prompt that already contains the relevant diff or file contents.
# Claude receives --tools "", preventing recursive collaboration or workspace reads.
claude_run_review() {
  local prompt_file="$1"
  local output_file="${2:-$(claude_tmp_path "claude-review-output-$$.md")}"
  local model="${3:-}"

  CLAUDE_COLLAB_CALLER=codex claude_run_print \
    "$prompt_file" \
    "$output_file" \
    "$model" \
    "" \
    "$CLAUDE_COLLAB_REVIEW_TIMEOUT" \
    "$CLAUDE_COLLAB_PROJECT_DIR" \
    "low" \
    "You are a read-only code reviewer invoked by Codex. This is a leaf invocation. Do not invoke Codex, call MCP tools, use slash commands, delegate via Bash, start collaboration sessions, edit files, or create plans. Read CLAUDE.md and project context for repository rules only. Follow the supplied review task, provide advisory output only, then stop."
}
