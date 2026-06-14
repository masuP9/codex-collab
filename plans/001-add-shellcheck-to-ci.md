# Plan 001: CI に shellcheck を追加し、既存の指摘をトリアージする

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat f5abf51..HEAD -- .github/workflows/ci.yml scripts/ hooks/ skills/claude-collab/scripts/`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S–M
- **Risk**: LOW
- **Depends on**: none
- **Category**: dx
- **Planned at**: commit `f5abf51`, 2026-06-11

## Why this matters

このリポジトリは scripts/・hooks/・skills/ 配下に合計約 2,900 行の bash を持ち、さらに commands/*.md に約 3,500 行の埋め込み bash があるが、CI（`.github/workflows/ci.yml`）は JSON/YAML lint とテスト実行のみで、シェルの静的解析が一切ない。クォート漏れや未定義変数のような bash 特有のバグはテストをすり抜けやすく、shellcheck はそれを最も安価に捕捉する手段。過去にも sed のエスケープ起因の障害（CLAUDE.md / メモリ記載の「Unmatched ( or \\(」問題）が起きており、静的解析の価値が実証されているコードベースである。

## Current state

- `.github/workflows/ci.yml` — `test` ジョブ（2つのテストスイート実行）と `lint` ジョブ（Python による JSON/YAML lint）のみ。shellcheck ステップは存在しない。
- 対象シェルスクリプト（すべて git 管理下）:
  - `scripts/codex-helpers.sh`（734行）— コアヘルパー
  - `scripts/test-helpers.sh`（1,341行）— テストスイート
  - `hooks/enforce-skill-usage.sh`（43行）— PreToolUse フック
  - `skills/claude-collab/scripts/claude-helpers.sh`
  - `skills/claude-collab/scripts/test-claude-helpers.sh`

`ci.yml` の lint ジョブは現在この形（抜粋）:

```yaml
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-python@v5
        with:
          python-version: '3.x'
```

リポジトリ規約: `scripts/codex-helpers.sh:136-138` の `sed $'s/\033\\[[0-9;]*[a-zA-Z]//g'` のような `$'...'` クォートは**意図的**（`\x1b` ヘックスエスケープは macOS sed で壊れるため）。shellcheck がこの周辺を指摘しても書き換えないこと。

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| shellcheck 導入（ローカル, WSL/Ubuntu） | `sudo apt-get install -y shellcheck` | exit 0（GitHub の ubuntu-latest ランナーにはプリインストール済み） |
| ベースライン確認 | `shellcheck scripts/*.sh hooks/*.sh skills/claude-collab/scripts/*.sh` | 初回は指摘が出る可能性あり |
| テスト | `bash scripts/test-helpers.sh` | `Results: 89 passed, 0 failed, 0 skipped` |
| テスト(claude) | `bash skills/claude-collab/scripts/test-claude-helpers.sh` | `claude helper tests passed` |

## Scope

**In scope**（変更してよいファイル）:
- `.github/workflows/ci.yml`
- `scripts/codex-helpers.sh`, `scripts/test-helpers.sh`, `hooks/enforce-skill-usage.sh`, `skills/claude-collab/scripts/claude-helpers.sh`, `skills/claude-collab/scripts/test-claude-helpers.sh` — shellcheck 指摘の修正のみ
- `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` — バージョン更新のみ

**Out of scope**:
- `commands/*.md` の埋め込み bash（Plan 003 が扱う）
- ヘルパー関数の挙動変更・リファクタリング（指摘修正は挙動を変えないこと）
- `tmp/` 配下すべて

## Git workflow

- Branch: `feat/ci-shellcheck`
- コミットは conventional commits 形式。例（`git log` より）: `fix: ensure LF line endings for hook scripts (v0.31.1)`
- push / PR 作成はオペレーターの指示があるまで行わない。

## Steps

### Step 1: ベースラインを取得する

`shellcheck scripts/*.sh hooks/*.sh skills/claude-collab/scripts/*.sh` を実行し、指摘の件数と SC コードの内訳を記録する。

**Verify**: コマンドが実行できること（指摘の有無は問わない）。指摘が 100 件を超える場合は STOP conditions 参照。

### Step 2: 指摘を修正する

- error / warning レベルを優先的に修正する。修正は挙動を変えないこと（クォート追加、`read -r`、未使用変数の削除など）。
- 意図的なパターン（例: `$'...'` クォートの sed、意図的な word splitting）には行単位の `# shellcheck disable=SCxxxx` を理由コメント付きで付ける。ファイル全体の disable は使わない。
- info / style レベルは、修正が自明なもののみ対応し、残りは disable で明示する。

**Verify**: `shellcheck scripts/*.sh hooks/*.sh skills/claude-collab/scripts/*.sh` → exit 0

### Step 3: 両テストスイートで回帰がないことを確認する

**Verify**: `bash scripts/test-helpers.sh` → `Results: 89 passed, 0 failed, 0 skipped` / `bash skills/claude-collab/scripts/test-claude-helpers.sh` → `claude helper tests passed`

### Step 4: CI にステップを追加する

`.github/workflows/ci.yml` の `lint` ジョブに、checkout の直後（Python セットアップの前）に追加:

```yaml
      - name: Shellcheck
        run: shellcheck scripts/*.sh hooks/*.sh skills/claude-collab/scripts/*.sh
```

（ubuntu-latest には shellcheck がプリインストールされているため install ステップは不要。）

**Verify**: ローカルで同じコマンドを実行 → exit 0。`python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/ci.yml'))"` → exit 0（YAML 構文確認）

### Step 5: バージョンを更新する

CLAUDE.md のルールに従い、`.claude-plugin/plugin.json` と `.claude-plugin/marketplace.json`（`plugins[0].version`）の **両方** をパッチバージョンアップ（変更前: `0.31.1` → 適切な次のパッチ。ただし他プランが先にマージ済みなら現行値から +1）。

**Verify**: `grep '"version"' .claude-plugin/plugin.json .claude-plugin/marketplace.json` → 両方が同一の新バージョン

## Test plan

新規テストは不要（静的解析の追加）。既存 2 スイートの全パスが回帰ゲート。

## Done criteria

- [ ] `shellcheck scripts/*.sh hooks/*.sh skills/claude-collab/scripts/*.sh` が exit 0
- [ ] `bash scripts/test-helpers.sh` → 89 passed, 0 failed
- [ ] `bash skills/claude-collab/scripts/test-claude-helpers.sh` → passed
- [ ] `.github/workflows/ci.yml` に Shellcheck ステップが存在する（`grep -n 'shellcheck' .github/workflows/ci.yml` がヒット）
- [ ] 2つの version ファイルが同一の新バージョン
- [ ] In scope 外のファイルに変更がない（`git status` で確認）
- [ ] `plans/README.md` のステータス行を更新

## STOP conditions

以下の場合は停止して報告すること（改変しない）:

- ベースラインの指摘が 100 件を超える（disable 乱発になるため、方針判断をオペレーターに戻す）。
- 指摘修正によりテストが失敗し、2回の修正試行で解消しない。
- `codex_strip_ansi`（`scripts/codex-helpers.sh:134-140`）の sed パターン書き換えが必要に見える場合（このパターンは意図的。disable で対応すること。書き換えが避けられないと判断したら STOP）。

## Maintenance notes

- 以後、新しい `.sh` を scripts/・hooks/・skills/*/scripts/ に追加したら CI の shellcheck 対象 glob が拾うか確認すること（glob を `find` ベースに広げるのは将来の改善余地）。
- Plan 004（ヘルパー堅牢化）はこのプランの後に実行すると、変更が自動的に lint される。
