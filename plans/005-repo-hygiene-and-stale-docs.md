# Plan 005: リポジトリ衛生 — .gitignore タイポ修正と stale な簡素化プラン文書の更新

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat f5abf51..HEAD -- .gitignore docs/plans/ CLAUDE.md`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P3
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: docs
- **Planned at**: commit `f5abf51`, 2026-06-11

## Why this matters

3 つの小さな衛生問題をまとめて片付ける:

1. **`.gitignore` のタイポ**: パターンが `.claude/.settings.local.json`（ドットが 1 つ余分）で、実ファイル `.claude/settings.local.json` にマッチしていない。現在はメンテナーのグローバル gitignore（`~/.config/git/ignore` の `**/.claude/settings.local.json`）に救われているだけで、他の環境でクローンするとローカル設定ファイルが誤コミット可能になる。
2. **stale なプラン文書**: `docs/plans/codebase-simplification.md` は Status が「計画立案完了（実装待ち）」だが、内容は v0.26 以前の旧アーキテクチャ（tmux 時代、codex-helpers.sh が 2,687 行/67 関数、既に削除された `collab-codex-attach.md`）を対象としており、その削減は v0.26.0（`7b3fe2e` tmux→codex exec 移行）と `c30d9b6`（collab-codex-attach 削除）で**実質完了している**。現在の codex-helpers.sh は 734 行/24 関数で、ほぼ全関数が使用されている。「実装待ち」のまま放置すると、将来のコントリビューター（や監査エージェント）が存在しない 2,000 行の負債を再調査してしまう。
3. **テスト手順が CLAUDE.md にない**: 検証コマンド 2 つ（`bash scripts/test-helpers.sh` / `bash skills/claude-collab/scripts/test-claude-helpers.sh`）が CLAUDE.md に記載されておらず、エージェントが毎回探すことになる。

## Current state

- `.gitignore` 該当行（コメント含む抜粋）:

```
# Claude Code local settings
.claude/.settings.local.json
```

- `docs/plans/codebase-simplification.md:1-4`:

```
# コードベース簡素化計画

Created: 2026-02-03
Status: 計画立案完了（実装待ち）
```

- 同文書には「codex-helpers.sh: 67関数定義…約1,400行の完全に使われていないコード」「collab-codex-attach.md 559行」等、現在のリポジトリに存在しない状態の記述がある（現状: `wc -l scripts/codex-helpers.sh` = 734、`commands/collab-codex-attach.md` は存在しない）。
- `CLAUDE.md` には「リリースワークフロー」「Codex 通信の仕様」「プロジェクト構造」「Bash 使用ルール」「ヘルパースクリプトの管理」セクションがあるが、テスト実行に関するセクションはない。

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| ignore 検証 | `git -c core.excludesFile=/dev/null check-ignore -v .claude/settings.local.json` | 修正後: `.gitignore:<n>` の行がマッチ元として表示される |
| テスト | `bash scripts/test-helpers.sh` | `Results: 89 passed, 0 failed, 0 skipped` |

## Scope

**In scope**:
- `.gitignore` — 1 行修正
- `docs/plans/codebase-simplification.md` — Status 行と追記のみ
- `CLAUDE.md` — テストセクション追加のみ
- `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` — バージョン更新（パッチ）

**Out of scope**:
- `docs/plans/codebase-simplification.md` の本文削除・書き換え（履歴的価値があるため、当時の記録は残す）
- `.claude/settings.local.json` ファイル自体（中身を読む必要も変更する必要もない）
- README.md

## Git workflow

- Branch: `fix/repo-hygiene`
- conventional commits 形式（例: `fix: correct .gitignore pattern and archive stale simplification plan (vX.Y.Z)`）
- push / PR 作成はオペレーターの指示があるまで行わない。

## Steps

### Step 1: .gitignore を修正する

`.claude/.settings.local.json` → `.claude/settings.local.json` に修正。

**Verify**: `git -c core.excludesFile=/dev/null check-ignore -v .claude/settings.local.json` → リポジトリの `.gitignore` の行番号が表示される（修正前はグローバル ignore を無効化すると何もマッチしない）

### Step 2: 簡素化プラン文書のステータスを実態に合わせる

`docs/plans/codebase-simplification.md` の `Status:` 行を更新し、直下に短い追記を入れる:

```
Status: 完了（v0.26.0〜v0.29.0 で実施済み — 本文書はアーカイブ）

> **2026-06 追記**: 本計画が対象としていた tmux ベースの旧アーキテクチャ
> （codex-helpers.sh 2,687行/67関数、collab-codex-attach.md）は、
> v0.26.0 の codex exec 移行（7b3fe2e）と collab-codex-attach 削除
> （c30d9b6）で除去済み。現行の codex-helpers.sh は 734行/24関数で、
> 本文書の調査結果は現在のコードベースには当てはまらない。
```

本文は変更しない。

**Verify**: `head -15 docs/plans/codebase-simplification.md` に新ステータスと追記が表示される。`grep -c '実装待ち' docs/plans/codebase-simplification.md` → 0

### Step 3: CLAUDE.md にテストセクションを追加する

「## ヘルパースクリプトの管理」セクションの直前に追加:

```markdown
## テスト

PR 作成前に以下の両方を実行し、全テストがパスすることを確認すること。

```sh
bash scripts/test-helpers.sh                              # ヘルパー関数のユニットテスト
bash skills/claude-collab/scripts/test-claude-helpers.sh  # claude-collab ヘルパーのテスト
```

- 純粋な bash のみで動作し、外部依存・実 codex 呼び出しはない
- CI（`.github/workflows/ci.yml`）でも同じ 2 スイートを実行している
- ヘルパー関数を追加・変更した場合は対応するテストを追加すること
```

**Verify**: `grep -n '## テスト' CLAUDE.md` がヒットする

### Step 4: 回帰確認とバージョン更新

両 version ファイルをパッチバージョンアップ。

**Verify**: `bash scripts/test-helpers.sh` → 89 passed / `grep '"version"' .claude-plugin/plugin.json .claude-plugin/marketplace.json` → 同一値

## Test plan

新規テストなし（docs + 設定 1 行）。既存スイートの全パスが回帰ゲート。

## Done criteria

- [ ] `git -c core.excludesFile=/dev/null check-ignore .claude/settings.local.json` → exit 0
- [ ] `grep -c '実装待ち' docs/plans/codebase-simplification.md` → 0
- [ ] `grep -n '## テスト' CLAUDE.md` → ヒット
- [ ] `bash scripts/test-helpers.sh` → 89 passed
- [ ] 変更ファイルが In scope のみ（`git status`）
- [ ] `plans/README.md` のステータス行を更新

## STOP conditions

- `.claude/settings.local.json` が**既に git 追跡されている**ことが判明した場合（`git ls-files .claude/` で確認。追跡済みなら ignore 修正だけでは不十分で、`git rm --cached` と中身の確認が必要になる — その判断はオペレーターに戻す）。2026-06-11 時点では未追跡であることを確認済み。
- `docs/plans/codebase-simplification.md` に、現行コードにまだ当てはまる未実施項目を見つけた場合（追記の文言を変える必要がある）。

## Maintenance notes

- 今後 `docs/plans/` に計画文書を置く場合は、完了時に Status を更新する規約をこの追記が実例として示す。
- `plans/`（本監査の成果物）と `docs/plans/`（過去の協調計画）は別物。混同しないこと。
