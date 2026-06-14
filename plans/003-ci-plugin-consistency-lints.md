# Plan 003: プラグイン整合性 lint を追加する（バージョン同期・コマンド md の bash ブロック検証）

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 25b7d22..HEAD -- .github/workflows/ci.yml commands/ scripts/ .claude-plugin/`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW（lint 追加は report → gate の段階導入。既存違反の修正のみ MED）
- **Depends on**: none（001 と独立。ただし 001 が先だと新スクリプトも shellcheck される）
- **Category**: dx
- **Planned at**: commit `25b7d22`, 2026-06-12（初版は `f5abf51`/2026-06-11。Plan 001/002 のマージ（PR #56, #57）によるドリフト — CI への Shellcheck / Run hook tests ステップ追加、scripts への shellcheck アノテーション、バージョン 0.31.3 — を反映して refresh 済み。commands/ は無変更でボイラープレート集計は初版どおり）

## Why this matters

このプラグインには機械的に守るべき不変条件が 3 つあるが、どれも CI で検証されていない:

1. **バージョン同期**: `.claude-plugin/plugin.json` と `.claude-plugin/marketplace.json` の version は常に一致しなければならない（CLAUDE.md のリリースルール）。現在は人間の注意力だけが頼り。
2. **CODEX_SKILL_CONTEXT マーカー**: commands/*.md の各 bash ブロックは先頭付近で `export CODEX_SKILL_CONTEXT=1` を行わないと、PreToolUse フックにブロックされる（CLAUDE.md に明記された規約）。新ブロック追加時に忘れると実行時に初めて壊れる。
3. **bash 構文**: commands/*.md には多数の bash ブロックが埋め込まれており（4ファイル合計約 3,500 行）、LLM がそのまま実行する。構文エラーは実行時まで発見されない。

さらに、ヘルパー読み込みのフォールバックチェーン（boilerplate）が 4 つのコマンドファイルに合計約 47 回複製されており、**既に複数の変種に分岐している**（`ls -td ~/.claude/plugins/cache/...` 行を含む完全形は codex-collab.md で 26 回中 13 回のみ）。チェーンを直すときに全箇所へ反映されたかを目視に頼っている。lint はこの drift を可視化する。

## Current state

- `.github/workflows/ci.yml` — `lint` ジョブは Shellcheck ステップ（Plan 001 で追加）+ Python による JSON / YAML 構文チェック。バージョン同期・コマンド md 検証はない。
- `.claude-plugin/plugin.json:3` — `"version": "0.31.3"`。`.claude-plugin/marketplace.json` — `plugins[0].version` が `"0.31.3"`。現在は一致している。
- commands/*.md の bash ブロックは ```` ```bash ```` フェンスで記述。`export CODEX_SKILL_CONTEXT=1` の出現回数: codex-collab.md=20, collab-planning.md=12, strong-inference.md=12, devils-advocate.md=11（2026-06-11 時点の grep -c。ブロック総数とは未照合 — Step 2 で照合する）。
- boilerplate の正規形（CLAUDE.md「ヘルパースクリプトの管理」セクション、および `commands/devils-advocate.md` 内の実例）:

```bash
HELPERS=""
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh" ]; then
  HELPERS="${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh"
elif [ -d ~/.claude/plugins/cache/codex-collab ]; then
  HELPERS=$(ls -td ~/.claude/plugins/cache/codex-collab/codex-collab/*/scripts/codex-helpers.sh 2>/dev/null | head -1)
fi
```

（後続の存在チェック行は `if`/一行形式の 2 変種が混在している。）

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| 新 lint 実行 | `bash scripts/lint-plugin.sh` | exit 0 |
| 既存テスト | `bash scripts/test-helpers.sh` | `Results: 89 passed, 0 failed, 0 skipped` |
| jq | `command -v jq` | あり（なければ `sudo apt-get install -y jq`） |

## Scope

**In scope**:
- `scripts/lint-plugin.sh`（新規作成）
- `.github/workflows/ci.yml` — lint ジョブへのステップ追加
- `commands/*.md` — **lint 違反の修正のみ**（マーカー追加、構文エラー修正、boilerplate の正規形への統一）。ワークフローのロジック・プロンプト文面は変更しない
- `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` — バージョン更新

**Out of scope**:
- `skills/**`（SKILL.md はトリガー定義であり実行ブロックの規約対象外）
- ヘルパー関数本体（`scripts/codex-helpers.sh`）
- boilerplate を外部ファイル化する試み（各 bash ブロックは独立したシェルで実行されるため、読み込みチェーン自体は各ブロックに必要。「鶏と卵」問題があるので共通化はしない — drift 検出に留める）

## Git workflow

- Branch: `feat/plugin-consistency-lints`
- conventional commits 形式
- push / PR 作成はオペレーターの指示があるまで行わない。

## Steps

### Step 1: lint スクリプトの骨格を作る

`scripts/lint-plugin.sh` を新規作成。3 つのチェックを関数として実装し、違反をファイル名・ブロック番号付きで列挙、違反ゼロなら exit 0:

1. **version 同期**: `jq -r '.version' .claude-plugin/plugin.json` と `jq -r '.plugins[0].version' .claude-plugin/marketplace.json` を比較。
2. **bash ブロック抽出 + 検査**: awk で commands/*.md から ```` ```bash ```` 〜 ```` ``` ```` の各ブロックを一時ファイルに抽出し、ブロックごとに:
   - `bash -n <block>` で構文チェック
   - ブロック内に `CODEX_SKILL_CONTEXT=1` が含まれるか確認
3. **boilerplate drift（警告のみ、exit code に影響させない）**: `HELPERS=""` で始まる連続行を抽出し、正規形（Current state 記載）と異なる変種の出現箇所を一覧表示。

抽出 awk の参考形:

```awk
/^```bash$/ { inblock=1; n++; file=sprintf("%s/block-%03d.sh", outdir, n); next }
/^```$/     { inblock=0; next }
inblock     { print > file }
```

### Step 2: report モードで現状を把握する

`bash scripts/lint-plugin.sh` を実行し、既存違反（構文エラー数、マーカー欠落ブロック数、drift 変種数）を記録する。

**Verify**: スクリプトが完走し、違反一覧が出力されること。

### Step 3: 既存違反を修正する

- マーカー欠落ブロック: ブロック先頭に `export CODEX_SKILL_CONTEXT=1` を追加。ただし**ヘルパーや codex CLI に一切触れない純粋な表示用ブロック**（例: 出力フォーマット例示）であれば、フェンス言語を ```` ```text ```` に変えて lint 対象から外す方が正しい。どちらか迷う場合はマーカー追加を選ぶ。
- 構文エラー: プレースホルダー（`[fix instructions]` のような擬似コード）が原因ならフェンスを ```` ```text ```` に変更。実コードの構文ミスなら最小修正。
- boilerplate 変種: 正規形に統一する（挙動同等の書き換えのみ）。

**Verify**: `bash scripts/lint-plugin.sh` → exit 0

### Step 4: CI に組み込む

`.github/workflows/ci.yml` の `lint` ジョブに追加:

```yaml
      - name: Plugin consistency lint
        run: bash scripts/lint-plugin.sh
```

**Verify**: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))"` → exit 0、ローカルで lint → exit 0

### Step 5: バージョンを更新する

両 JSON をマイナーバージョンアップ（新機能 = lint 追加。0.31.3 → 0.32.0）。

**Verify**: `bash scripts/lint-plugin.sh` → exit 0（version 同期チェック自体が検証になる）

## Test plan

- lint スクリプト自体の自己検証: 意図的に壊した一時コピー（version 不一致 / マーカー欠落ブロック）で非ゼロ exit することを手元で確認してから commit する（テストファイル化は不要、確認手順をコミットメッセージか PR 説明に記載）。
- 既存スイート: `bash scripts/test-helpers.sh` → 89 passed（commands 修正がヘルパーに影響しないことの確認）。

## Done criteria

- [ ] `bash scripts/lint-plugin.sh` → exit 0
- [ ] version 不一致を意図的に作ると exit 非ゼロになる（手元確認）
- [ ] `bash scripts/test-helpers.sh` → 89 passed
- [ ] CI の lint ジョブに `Plugin consistency lint` ステップが存在
- [ ] commands/*.md の変更が lint 違反修正に限られている（`git diff commands/` をレビューし、プロンプト文面・ワークフロー手順の変更がないこと）
- [ ] `plans/README.md` のステータス行を更新

## STOP conditions

- Step 2 の report で構文エラーが 5 ブロックを超える場合（埋め込み bash が想定以上に擬似コード混じりで、このアプローチ自体の再検討が必要）。
- マーカー欠落の修正がワークフローの実行順序やフックの挙動を変えてしまうと判断した場合。
- bash ブロックの抽出で、ネストしたフェンス（ブロック内に ```` ``` ```` を含む）が原因で抽出が壊れるファイルがある場合は、そのファイルを skip リストに入れて報告（黙って対象から落とさない）。

## Maintenance notes

- 新コマンド md を追加する際は、この lint が CODEX_SKILL_CONTEXT 規約を自動強制する。CLAUDE.md の該当注記は据え置きでよい。
- boilerplate drift チェックは警告どまり。将来チェーンを変更する PR では、この警告出力を見て全 47 箇所が更新されたか確認する運用。
- Plan 001 はマージ済みのため、`scripts/lint-plugin.sh` は CI の shellcheck 対象（`scripts/*.sh`）に含まれる — `shellcheck --source-path=SCRIPTDIR -x scripts/*.sh` をローカル実行して exit 0 を確認してから commit すること。
