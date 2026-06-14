# Plan 007: フックの検出対象を副作用持ち 4 関数に縮小し、ソフトガードとして再定義する

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: Step 0 がこのプランの drift check を兼ねる。
> `hooks/enforce-skill-usage.sh` の 22 行目が「Current state」の excerpt と
> 一致しない場合は STOP。

## Status

- **Priority**: P3
- **Effort**: S–M
- **Risk**: LOW（検出範囲の縮小であり、このフックはセキュリティ境界ではない LLM 誘導ソフトガード。検出漏れの増加は設計上許容済み）
- **Depends on**: plans/006（PR #61。**マージ済みであることが前提** — Step 0 で検証）
- **Category**: dx
- **Planned at**: main `179bf5a` + PR #61（commit `cd9218f`、v0.32.2）の合成状態、2026-06-12
- **背景**: Devil's Advocate レビュー（tmp/devils-advocate/20260612-120332-24936.md、verdict: CONDITIONAL）の承認条件 1–6 を実装に落としたもの

## Why this matters

現行フックは codex_* ヘルパー**全関数** + `source`/`HELPERS=`/`$HELPERS`/`CODEX_PROMPT` の広域パターンを検出するが、このうち守る価値があるのは副作用を持つ関数（外部モデル実行・レビュー実行・セッション状態書き込み）だけである。純粋変換関数（codex_strip_ansi 等）や推測的パターン（`HELPERS=` 等）の検出は誤検知リスクと維持コストだけを生む。また、マーカー判定が「コマンド文字列のどこかに `CODEX_SKILL_CONTEXT=1` が含まれるか」という部分文字列一致のため、引用テキスト内の言及でもバイパスが成立してしまう。本プランで検出対象を 4 関数に限定し、マーカー判定を行頭の明示的 `export` に厳格化し、フックの目的を「内部 API の偶発的誤用を防ぐソフトガード」として文書・ブロック文言に明記する。

## Current state

前提: PR #61（Plan 006）マージ後の main。

- `hooks/enforce-skill-usage.sh`（44 行）— 判定部分（19–28 行目）:

```bash
# Skill context marker — allow everything
echo "$COMMAND" | grep -qF 'CODEX_SKILL_CONTEXT=1' && exit 0

# Check for codex-collab patterns
PATTERN='(^|[;&|]|\$\(|`)[[:space:]]*codex_[A-Za-z0-9_]+'
PATTERN="$PATTERN"'|\bsource\b.*codex-helpers\.sh'
PATTERN="$PATTERN"'|\.[ \t]+.*codex-helpers\.sh'
# shellcheck disable=SC2016 # $HELPERS is a literal grep pattern (single-quoted intentionally, not a variable)
PATTERN="$PATTERN"'|\$HELPERS.*codex-helpers'
PATTERN="$PATTERN"'|HELPERS=.*codex-helpers'
PATTERN="$PATTERN"'|\bCODEX_PROMPT\b'
```

ブロック時メッセージ（31–40 行目）は「This Bash command uses codex-collab helper functions directly.」で始まる heredoc。

- `hooks/test-enforce-skill-usage.sh`（v0.32.2 で 17 ケース）— `run_hook "<command string>"` ヘルパーが JSON を組んでフックに流し exit code を echo する構造。ケース 3/4/5/7 が source・dot-source・`HELPERS=`・`CODEX_PROMPT` のブロックを、ケース 6 が `export CODEX_SKILL_CONTEXT=1; codex_run_exec x` のマーカー許可を、ケース 16 が `cat out.txt | codex_strip_ansi` のブロックを検証している。
- `docs/bash-usage.md` — 「## Detection Patterns」の表（4 行）、「### Known Limitations」、「## What Happens When Blocked」セクション。
- `hooks/enforce-skill-usage.md`（77 行）— フックの検出ロジックを説明する文書。検出パターンの記述が本体と同期している必要がある。
- マーカーの正規利用形状（コードベース実態）: commands/*.md の全 bash ブロックが**行頭**で `export CODEX_SKILL_CONTEXT=1` を実行する（直前にコメント行あり。例: commands/devils-advocate.md:24）。エージェントの一時利用も `export CODEX_SKILL_CONTEXT=1; <cmd>` の行頭前置。**どちらも「いずれかの行が export で始まる」形**であり、「コマンド文字列の最初の文字から」ではないことに注意。

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| フックテスト | `bash hooks/test-enforce-skill-usage.sh` | 全ケース pass、exit 0 |
| ヘルパーテスト | `bash scripts/test-helpers.sh` | 99 passed, 0 failed |
| 整合性 lint | `bash scripts/lint-plugin.sh` | PASS, exit 0 |
| 構文チェック | `bash -n hooks/enforce-skill-usage.sh && bash -n hooks/test-enforce-skill-usage.sh` | exit 0（shellcheck はローカルに無ければ CI に委ねる） |

## Scope

**In scope**:
- `hooks/enforce-skill-usage.sh` — マーカー判定（19 行目）と検出パターン（22–28 行目）、ブロックメッセージ（31–40 行目）
- `hooks/test-enforce-skill-usage.sh` — 期待値の更新 + 新ケース追加
- `hooks/enforce-skill-usage.md` — 検出ロジック記述の同期
- `docs/bash-usage.md` — Detection Patterns 表・Known Limitations・ブロックメッセージ例・sunset 基準の追記
- `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` — **マイナー** バージョンアップ（現行値 0.32.x → 0.33.0。挙動変更のため）

**Out of scope**:
- `commands/*.md`, `skills/`, `CLAUDE.md` — マーカーの正規利用形状（行頭 export）は新判定でもそのまま通るため変更不要
- `scripts/codex-helpers.sh` — 関数自体には触れない
- フックのプロトコル（exit code 体系、jq fail-open、plugin.json のフック登録）
- 検出の「強化」（bash -c・env・alias 等の間接実行検出を足さない — fail-open 設計の許容トレードオフ）

## Git workflow

- Branch: `feat/hook-scope-reduction`
- conventional commits 形式（例: `feat: reduce hook detection to side-effect helpers (v0.33.0)`）
- push / PR 作成はオペレーターの指示があるまで行わない。

## Steps

### Step 0: 前提検証（drift check）

`grep -n "PATTERN='" hooks/enforce-skill-usage.sh | head -1` を実行し、22 行目が
`PATTERN='(^|[;&|]|\$\(|`)[[:space:]]*codex_[A-Za-z0-9_]+'` であることを確認する。

**Verify**: 上記が一致 → 続行。`\bcodex_[A-Za-z0-9_]+\b`（旧広域パターン）の場合は **PR #61 が未マージ**なので STOP。

### Step 1: マーカー判定の厳格化

19 行目:

```bash
echo "$COMMAND" | grep -qF 'CODEX_SKILL_CONTEXT=1' && exit 0
```

を次に置換（**いずれかの行**が、前置空白を許して `export CODEX_SKILL_CONTEXT=1` で始まる場合のみ許可）:

```bash
echo "$COMMAND" | grep -qE '^[[:space:]]*export[[:space:]]+CODEX_SKILL_CONTEXT=1' && exit 0
```

直前のコメントを `# Skill context marker — soft guard opt-in, only honored at line start` に更新する。

**Verify**: `bash hooks/test-enforce-skill-usage.sh` → ケース 6 は pass のまま（マーカーが行頭 export のため）。他ケースの結果は変わらない。

### Step 2: 検出パターンを 4 関数に縮小

22–28 行目の PATTERN 構築 7 行をすべて削除し、次の 1 行 + コメントに置換:

```bash
# Soft guard: only side-effect helpers (external execution / review / session-state writes).
# Pure transforms (codex_strip_ansi etc.) and speculative patterns (HELPERS=, CODEX_PROMPT)
# are intentionally NOT guarded — see docs/bash-usage.md "Sunset criteria".
PATTERN='(^|[;&|]|\$\(|`)[[:space:]]*codex_(run_exec|run_review|save_session_state|save_thread)\b'
```

実行位置アンカー部 `(^|[;&|]|\$\(|`)[[:space:]]*` は既存（Plan 006）のまま流用すること。

**Verify**: `bash hooks/test-enforce-skill-usage.sh` → この時点でケース 3・4・5・7・16 が fail する（期待値が旧挙動のため）。ケース 2・14・15・17（codex_run_exec の実行）は pass のまま。**ケース 2 が fail したら STOP**（パターンの書き誤り）。

### Step 3: ブロックメッセージの再定義

31–40 行目の heredoc を次に置換:

```
This command calls a codex-collab side-effect helper directly
(codex_run_exec / codex_run_review / codex_save_session_state / codex_save_thread).

This is a soft guard against accidental direct use of internal APIs,
not a security boundary. Preferred entry points:
- /codex-collab [task] - Start collaboration
- /strong-inference [problem] - Investigate problems
- /devils-advocate [proposal] - Stress-test designs

If you are doing this intentionally, start the line with:
  export CODEX_SKILL_CONTEXT=1; <your command>

See docs/bash-usage.md for details.
```

**Verify**: `bash -n hooks/enforce-skill-usage.sh` → exit 0

### Step 4: テストを新挙動に更新

`hooks/test-enforce-skill-usage.sh` を更新:

1. **期待値の反転（2 → 0、コメントも「縮小により非対象」に更新）**: ケース 3（source）、ケース 4（dot-source）、ケース 5（`HELPERS=`）、ケース 7（`CODEX_PROMPT`）、ケース 16（`cat out.txt | codex_strip_ansi` — 純粋変換は非対象）。
2. **新ケースを追加**:

| # | 入力 command | 期待 | 検証内容 |
|---|--------------|------|---------|
| 18 | `cat out.txt \| codex_run_review` | 2 | 対象関数のパイプ先実行は検出維持（旧ケース 16 の対象関数版） |
| 19 | `codex_strip_ansi < raw.txt` | 0 | 非対象ヘルパーの行頭実行は許可 |
| 20 | `codex_save_thread t1 thread-x` | 2 | 状態書き込み関数の行頭実行は検出 |
| 21 | `echo "CODEX_SKILL_CONTEXT=1"; codex_run_exec x` | 2 | 部分文字列のマーカー言及ではバイパスできない（行頭 export のみ有効） |
| 22 | 複数行（1 行目 `# setup`、2 行目 `export CODEX_SKILL_CONTEXT=1`、3 行目 `codex_run_exec x`） | 0 | コメント行の後の行頭 export を認識（commands/*.md の実形状） |

ケース 22 は `printf '# setup\nexport CODEX_SKILL_CONTEXT=1\ncodex_run_exec x'` で構成する。既存ケース 11–13（言及許可）・14–15・17（実行検出）は無変更で pass し続けること。

**Verify**: `bash hooks/test-enforce-skill-usage.sh` → 22 ケース全 pass、exit 0

### Step 5: 文書の同期

1. `docs/bash-usage.md`:
   - 「## Detection Patterns」の表を 1 行に置換: パターン `(^\|[;&\|]\|\$\(\|`)[[:space:]]*codex_(run_exec\|run_review\|save_session_state\|save_thread)\b`、Description「Side-effect helper calls at execution position (external execution / review / session-state writes)」、Limitation「Pure transforms and mentions in argument text are allowed」。
   - マーカーの説明箇所を「a line starting with `export CODEX_SKILL_CONTEXT=1`（substring mentions are ignored）」に更新。
   - 「### Known Limitations」を更新: source・`HELPERS=`・`CODEX_PROMPT`・純粋変換ヘルパーは**意図的に非対象**（ソフトガードの目的外）と明記。間接実行（`bash -c` 等）非検出の記述は維持。
   - 新セクション「### Sunset criteria」を Known Limitations の直後に追加: 「このフックは次のいずれかが観測された場合、全廃を再検討する: (1) 修正困難な誤検知の反復、(2) 記録された複数のブロックがすべて機械的なマーカー付与で終わりスキル誘導に至らない、(3) スキル誘導の成功例がないまま維持作業が継続する。ブロック発生時は PR か issue に実例を手動記録すること（恒久計測基盤は作らない）。」
   - 「## What Happens When Blocked」のメッセージ例を Step 3 の新文言に差し替え。
2. `hooks/enforce-skill-usage.md`: 検出ロジックの記述（検出パターン・マーカー判定）を新実装に合わせて更新。description フィールドも「Soft guard against accidental direct use of codex-collab side-effect helpers」に更新。

**Verify**: `grep -c 'run_exec|run_review' docs/bash-usage.md hooks/enforce-skill-usage.md` → 各ファイル 1 以上。`grep -n 'Sunset criteria' docs/bash-usage.md` → ヒット。

### Step 6: 全ゲート + バージョン更新

両 version ファイルを **0.33.0**（マイナー）に更新。

**Verify**:
- `bash hooks/test-enforce-skill-usage.sh` → 22 ケース pass、exit 0
- `bash scripts/test-helpers.sh` → 99 passed, 0 failed
- `bash scripts/lint-plugin.sh` → PASS（version 同期含む）
- `bash -n hooks/*.sh` → exit 0（shellcheck があれば `shellcheck --source-path=SCRIPTDIR -x hooks/*.sh` も）

## Test plan

Step 4 の表が本体。検証の核は 3 点: (1) 非対象化した 5 形状（ケース 3/4/5/7/16）が許可に変わる、(2) 対象 4 関数の実行 6 形状（ケース 2/14/15/17/18/20）がブロックされ続ける、(3) マーカーが「行頭 export のみ」になり、部分文字列バイパス（ケース 21）が塞がれつつ正規形状（ケース 6/22）は通る。

## Done criteria

- [ ] `bash hooks/test-enforce-skill-usage.sh` → 22 ケース以上すべて pass、exit 0
- [ ] ケース 3・4・5・7・16 の期待値が 0（非対象）に反転している
- [ ] ケース 21（部分文字列マーカーの無効化）とケース 22（行頭 export 認識）が含まれている
- [ ] `grep -c 'HELPERS\|CODEX_PROMPT' hooks/enforce-skill-usage.sh` → 0（広域パターンの削除）
- [ ] `bash scripts/test-helpers.sh` → 0 failed
- [ ] `bash scripts/lint-plugin.sh` → PASS
- [ ] `docs/bash-usage.md` に「Sunset criteria」セクションが存在し、Detection Patterns 表が実装と一致
- [ ] `hooks/enforce-skill-usage.md` の検出ロジック記述が実装と一致
- [ ] 2 つの version ファイルが両方 `0.33.0`
- [ ] `plans/README.md` のステータス行を更新

## STOP conditions

- Step 0 で 22 行目が旧広域パターン `\bcodex_[A-Za-z0-9_]+\b` のまま（PR #61 未マージ）。
- Step 1 の置換後にケース 6 が fail する（マーカー正規形状を壊している — 正規表現の `[[:space:]]+` と `=1` の間の書き方を確認して 2 回まで修正、解消しなければ STOP）。
- Step 2 の置換後にケース 2・14・15・17 のいずれかが fail する（4 関数アルタネーションの書き誤り）。
- commands/*.md のいずれかの bash ブロックが「行頭 export」以外の形でマーカーを設定していることを発見した場合（本プランの前提が崩れる。該当箇所を報告して STOP — commands/*.md の変更はスコープ外）。

## Maintenance notes

- **このフックはソフトガードであり、検出漏れを塞ぐ方向の変更には実害の証拠を要求すること**（Devil's Advocate レビューの合意事項）。検出対象を広げる PR が来たら、それが 2026-06-12 に解消した誤検知問題の再導入でないかを確認する。
- 保護対象 4 関数は「外部実行 + 状態書き込み」という分類に基づく。`scripts/codex-helpers.sh` に新しい副作用関数（外部プロセス起動・ファイル書き込み）が追加されたら、アルタネーションへの追加を検討する。純粋変換・読み取り系は追加しない。
- **Sunset 条項**: docs/bash-usage.md の「Sunset criteria」に該当する観測が貯まったら、フック全体（本体・テスト・docs・plugin.json の hooks 登録）の削除プランを起こす。
- レビューで見るべき点: ケース 21/22 が本当に新マーカー判定を検証していること、docs 2 ファイルと実装のパターン文字列が一致していること、ブロックメッセージに「soft guard」「not a security boundary」の文言があること。
