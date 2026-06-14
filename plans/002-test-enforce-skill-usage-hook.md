# Plan 002: PreToolUse フック enforce-skill-usage.sh にテストを追加する

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat b5a434c..HEAD -- hooks/ .github/workflows/ci.yml`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: tests
- **Planned at**: commit `b5a434c`, 2026-06-12（初版は `f5abf51`/2026-06-11。Plan 001 マージ（PR #56）によるドリフト — CI への shellcheck ステップ追加とフックへの disable コメント1行 — を反映して refresh 済み）

## Why this matters

`hooks/enforce-skill-usage.sh` は「ヘルパー関数はスキル経由でのみ実行する」というこのプラグインの唯一のガードレールだが、テストが一切ない（`scripts/test-helpers.sh` はヘルパー関数のみを対象とし、フックへの言及はゼロ）。このフックは jq 不在・JSON 不正時に fail-open（exit 0 = 許可）する設計のため、パターンマッチの regression が起きても**静かに無効化されるだけ**で誰も気づかない。過去に v0.31.1 で LF 改行問題の修正が入っており（コミット `ae17fc5`）、フックは実際に壊れた前歴がある。少数のテーブル駆動テストで回帰を恒久的に防げる。

## Current state

- `hooks/enforce-skill-usage.sh`（44行）— PreToolUse command フック。プロトコル: stdin に JSON（`.tool_input.command`）、exit 0 = 許可、exit 2 = ブロック（stderr がユーザーに表示される）。

全文の要点（`hooks/enforce-skill-usage.sh:11-30`）:

```bash
# Require jq for JSON parsing; fail open if unavailable
command -v jq &>/dev/null || exit 0

# Read and extract command from tool input
COMMAND=$(jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[ -z "$COMMAND" ] && exit 0

# Skill context marker — allow everything
echo "$COMMAND" | grep -qF 'CODEX_SKILL_CONTEXT=1' && exit 0

# Check for codex-collab patterns
PATTERN='\bcodex_[A-Za-z0-9_]+\b'
PATTERN="$PATTERN"'|\bsource\b.*codex-helpers\.sh'
PATTERN="$PATTERN"'|\.[ \t]+.*codex-helpers\.sh'
# shellcheck disable=SC2016 # $HELPERS is a literal grep pattern (single-quoted intentionally, not a variable)
PATTERN="$PATTERN"'|\$HELPERS.*codex-helpers'
PATTERN="$PATTERN"'|HELPERS=.*codex-helpers'
PATTERN="$PATTERN"'|\bCODEX_PROMPT\b'

if echo "$COMMAND" | grep -qE "$PATTERN"; then
  ...
  exit 2
fi
exit 0
```

- テストハーネスの規約: `scripts/test-helpers.sh` 冒頭に `pass()` / `fail()` / `skip()`（色付き echo + カウンタ）が定義され、最後に `Results: N passed, M failed, K skipped` を出力し、failed > 0 なら exit 1。新テストはこのパターンを踏襲すること（実装前に `scripts/test-helpers.sh` の先頭 60 行を読むこと）。
- CI（`.github/workflows/ci.yml`）の `test` ジョブは現在 2 ステップ: `bash scripts/test-helpers.sh` と `bash skills/claude-collab/scripts/test-claude-helpers.sh`。

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| 新テスト実行 | `bash hooks/test-enforce-skill-usage.sh` | 全テスト pass、exit 0 |
| 既存テスト | `bash scripts/test-helpers.sh` | `Results: 89 passed, 0 failed, 0 skipped` |
| jq 確認 | `command -v jq` | パスが表示される（ubuntu-latest にはプリインストール） |

## Scope

**In scope**:
- `hooks/test-enforce-skill-usage.sh`（新規作成）
- `.github/workflows/ci.yml` — test ジョブへの 1 ステップ追加のみ
- `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` — バージョン更新のみ

**Out of scope**:
- `hooks/enforce-skill-usage.sh` 本体の変更（テストが現状の挙動を固定するのが目的。フックの挙動が「おかしい」と感じても変更しない — それは別プランの仕事）
- `scripts/test-helpers.sh`

## Git workflow

- Branch: `feat/hook-tests`
- conventional commits 形式（例: `feat: add tests for enforce-skill-usage hook (vX.Y.Z)`）
- push / PR 作成はオペレーターの指示があるまで行わない。

## Steps

### Step 1: テストファイルを作成する

`hooks/test-enforce-skill-usage.sh` を新規作成。`scripts/test-helpers.sh` の pass/fail ハーネスパターンを最小限で複製し、ヘルパー関数 `run_hook()` を定義する:

```bash
HOOK="$(cd "$(dirname "$0")" && pwd)/enforce-skill-usage.sh"

# run_hook "<command string>" → フックを実行し exit code を返す
run_hook() {
  printf '{"tool_input":{"command":%s}}' "$(printf '%s' "$1" | jq -Rs .)" \
    | bash "$HOOK" >/dev/null 2>&1
  echo $?
}
```

以下のケースを必ず含める（期待 exit code 付き）:

| # | 入力 command | 期待 |
|---|--------------|------|
| 1 | `ls -la` | 0（無関係なコマンドは許可） |
| 2 | `codex_run_exec prompt.txt` | 2（ヘルパー直接呼び出しをブロック） |
| 3 | `source scripts/codex-helpers.sh` | 2 |
| 4 | `. ./scripts/codex-helpers.sh` | 2 |
| 5 | `HELPERS=scripts/codex-helpers.sh` | 2 |
| 6 | `export CODEX_SKILL_CONTEXT=1; codex_run_exec x` | 0（スキルコンテキストマーカーで許可） |
| 7 | `echo $CODEX_PROMPT` | 2（CODEX_PROMPT パターン） |
| 8 | 空 JSON `{}`（command なし） | 0（fail open） |
| 9 | 不正 JSON `not-json` | 0（fail open） |
| 10 | `codex exec -s read-only - < p.txt` | 0（`codex_` プレフィックスなしの codex CLI 自体はブロックされない） |
| 11 | `gh pr create --body-file body.md --title "fix codex_strip_ansi"` | 2（**既知の誤検知の固定化**。引数テキスト中の関数名への単なる言及でも `\bcodex_\w+\b` がマッチしブロックされる。2026-06-12 に実際の PR 作成で発生を確認済み） |

ケース 8・9 は `run_hook` を使わず生の文字列を直接 `bash "$HOOK"` にパイプすること。

ケース 11 は望ましい挙動ではなく**現状の挙動**を固定する characterization テスト。期待値を 0 に書き換えてフック側を「修正」しないこと（パターン改善は本プランのスコープ外 — Maintenance notes 参照）。テストコードには `# NOTE: 既知の誤検知を固定化（パターン改善時はこの期待値を 0 に変える）` のコメントを付ける。

**Verify**: `bash hooks/test-enforce-skill-usage.sh` → 全ケース pass、exit 0

### Step 2: CI に組み込む

`.github/workflows/ci.yml` の `test` ジョブ末尾に追加:

```yaml
      - name: Run hook tests
        run: bash hooks/test-enforce-skill-usage.sh
```

**Verify**: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))"` → exit 0

### Step 3: バージョンを更新する

`.claude-plugin/plugin.json` と `.claude-plugin/marketplace.json`（`plugins[0].version`）の両方をパッチバージョンアップ。

**Verify**: `grep '"version"' .claude-plugin/plugin.json .claude-plugin/marketplace.json` → 両方同一値

## Test plan

このプラン自体がテスト追加。上表 11 ケースが最低ライン。構造は `scripts/test-helpers.sh` のハーネス（pass/fail カウンタ + 最終サマリ + failed>0 で exit 1）に合わせる。

## Done criteria

- [ ] `bash hooks/test-enforce-skill-usage.sh` → 11 ケース以上すべて pass、exit 0
- [ ] テスト 8・9（fail-open）とテスト 11（誤検知の characterization）が含まれている
- [ ] `bash scripts/test-helpers.sh` → 89 passed（回帰なし）
- [ ] CI に `Run hook tests` ステップが存在
- [ ] 2つの version ファイルが同一の新バージョン
- [ ] `hooks/enforce-skill-usage.sh` 本体に diff がない（`git diff hooks/enforce-skill-usage.sh` が空）
- [ ] `plans/README.md` のステータス行を更新

## STOP conditions

- ケース 1〜10 のいずれかで、フックの実際の挙動が上表の期待値と異なる場合（= フック本体のバグ発見）。テストを期待値側に書き換えて誤魔化さず、STOP して実挙動を報告すること。
- jq がローカルにない場合はインストール（`sudo apt-get install -y jq`）し、それも不可なら STOP。

## Maintenance notes

- フックの `PATTERN` に新パターンを追加する際は、このテストにケースを追加するのが規約となる。
- ケース 6 が示すとおり、マーカー文字列はコマンド内のどこにあっても許可になる。これはスキル設計上の意図（LLM への誘導であり、セキュリティ境界ではない — `docs/bash-usage.md` 参照）。テストで「バイパス可能」を発見扱いしないこと。
- **既知の誤検知（ケース 11）**: `\bcodex_[A-Za-z0-9_]+\b` はコマンドの**引数テキスト**に関数名が現れただけでマッチする。実例: 2026-06-12、PR #56 作成時に PR 本文へ `codex_strip_ansi` 等を含む `gh pr create --body "..."` がブロックされた（`--body-file` で回避）。パターン改善（例: `^gh |^git ` で始まるコマンドの除外、またはヘルパー名が「実行位置」にある場合のみマッチさせる）は挙動変更なので本プランのスコープ外。改善する場合は別プランを起こし、ケース 11 の期待値を 0 に反転させること。
