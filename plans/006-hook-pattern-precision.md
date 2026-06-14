# Plan 006: フックの関数名検出を実行位置にアンカーし、引数テキストの誤検知を解消する

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat a54f1d9..HEAD -- hooks/ docs/bash-usage.md`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P3
- **Effort**: S
- **Risk**: LOW–MED（誤検知の解消とトレードオフで検出漏れが増えるが、このフックは LLM 誘導でありセキュリティ境界ではないため、検出漏れのコストは低い）
- **Depends on**: plans/002（DONE — フックのテストが存在することが前提）
- **Category**: dx
- **Planned at**: commit `a54f1d9`, 2026-06-12

## Why this matters

フックの関数名検出 `\bcodex_[A-Za-z0-9_]+\b` は、コマンド文字列の**どこに**関数名が現れてもブロックする。このため「関数名に言及するだけ」の正当なコマンドが繰り返しブロックされている。2026-06-12 だけで実害 3 件:

1. `gh pr create --body "...codex_strip_ansi..."` がブロック（PR #56 作成時。`--body-file` で回避）
2. `grep -n 'codex_json_escape()...' scripts/codex-helpers.sh` がブロック（コード調査時。パターン書き換えで回避）
3. `git commit -m "fix: harden codex_json_escape..."` がブロック（Plan 004 実行時。マーカー付与で回避）

このリポジトリ自体が codex_* 関数を扱うため、コミットメッセージ・PR 本文・検索パターンに関数名が頻出する。検出を「実行位置」（行頭、`;` `&` `|` の後、`$(` / バッククォートの中）にアンカーすれば、言及と実行を区別できる。

## Current state

- `hooks/enforce-skill-usage.sh`（44行）— 検出パターン部分（22-28行）:

```bash
PATTERN='\bcodex_[A-Za-z0-9_]+\b'
PATTERN="$PATTERN"'|\bsource\b.*codex-helpers\.sh'
PATTERN="$PATTERN"'|\.[ \t]+.*codex-helpers\.sh'
# shellcheck disable=SC2016 # $HELPERS is a literal grep pattern (single-quoted intentionally, not a variable)
PATTERN="$PATTERN"'|\$HELPERS.*codex-helpers'
PATTERN="$PATTERN"'|HELPERS=.*codex-helpers'
PATTERN="$PATTERN"'|\bCODEX_PROMPT\b'
```

判定は `echo "$COMMAND" | grep -qE "$PATTERN"`(30行) — grep は行単位で評価するため、複数行コマンドでは各行の行頭が `^` にマッチする。

- `hooks/test-enforce-skill-usage.sh`（163行+）— Plan 002 で追加された 11 ケース。**ケース 11** が現状の誤検知を characterization として固定しており、テストコードに `# NOTE: 既知の誤検知を固定化（パターン改善時はこの期待値を 0 に変える）` のコメントがある。本プランがその「パターン改善時」に該当する。
- `docs/bash-usage.md` — 「## Detection Patterns」セクション（60-69行）にパターン表、「### Known Limitations」(71-74行) に既知の制限が記載されている。パターン変更に合わせて更新が必要。

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| フックテスト | `bash hooks/test-enforce-skill-usage.sh` | 全ケース pass、exit 0 |
| ヘルパーテスト | `bash scripts/test-helpers.sh` | 0 failed（ケース数は main の現行値） |
| 整合性 lint | `bash scripts/lint-plugin.sh` | PASS, exit 0 |
| shellcheck | `shellcheck --source-path=SCRIPTDIR -x hooks/*.sh` | exit 0 |

## Scope

**In scope**:
- `hooks/enforce-skill-usage.sh` — 関数名パターン（22行目）の置換のみ
- `hooks/test-enforce-skill-usage.sh` — ケース 11 の期待値反転 + 新ケース追加
- `docs/bash-usage.md` — Detection Patterns 表と Known Limitations の更新
- `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` — パッチバージョンアップ（現行値から +1）

**Out of scope**:
- 22行目以外のパターン（`source`/`HELPERS=`/`$HELPERS`/`CODEX_PROMPT`）— 実際の読み込み・参照構文を対象としており、誤検知の実害報告がない。`HELPERS=` がメッセージテキスト内で誤検知しうる理論上の問題は Known Limitations に記載するに留める
- フックのプロトコル（exit code、fail-open 動作、マーカー判定）
- `commands/*.md`, `CLAUDE.md`

## Git workflow

- Branch: `fix/hook-pattern-precision`
- conventional commits 形式（例: `fix: anchor helper-name detection to execution position (vX.Y.Z)`）
- **コミット時の注意**: コミットメッセージに codex_* 関数名を含めるとフック（修正前）がブロックすることがある。メッセージに関数名を書かないか、`--body-file` 同様にメッセージを簡潔に保つこと
- push / PR 作成はオペレーターの指示があるまで行わない。

## Steps

### Step 1: 新パターンへの置換

`hooks/enforce-skill-usage.sh` の 22 行目:

```bash
PATTERN='\bcodex_[A-Za-z0-9_]+\b'
```

を次に置換する（実行位置: 行頭 / `;` `&` `|` の直後 / `$(` の直後 / バッククォートの直後。前置空白を許容）:

```bash
PATTERN='(^|[;&|]|\$\(|`)[[:space:]]*codex_[A-Za-z0-9_]+\b'
```

置換にあたり、24行目の `\.[ \t]+.*codex-helpers\.sh` 等、他のパターン行には触れないこと。

**Verify**: `bash hooks/test-enforce-skill-usage.sh` → この時点ではケース 11 が fail する（期待値がまだ 2 のため）。それ以外の 10 ケースは pass のまま。

### Step 2: テストを新挙動に更新する

`hooks/test-enforce-skill-usage.sh` を更新:

1. **ケース 11 の期待値を 2 → 0 に反転**し、NOTE コメントを「パターン改善（Plan 006）により引数テキスト中の言及は許可される」旨に書き換える。
2. 以下の新ケースを追加（実際に観測された 3 インシデントの再現 + 検出維持の確認）:

| # | 入力 command | 期待 | 検証内容 |
|---|--------------|------|---------|
| 12 | `git commit -m "fix: harden codex_json_escape handling"` | 0 | インシデント3の再現（言及は許可） |
| 13 | `grep -n 'codex_json_escape()' scripts/codex-helpers.sh` | 0 | インシデント2の再現（注意: このコマンド文字列は `codex-helpers\.sh` 単体ではどのパターンにも一致しない。`source`/ドット/`HELPERS=` を伴わないため） |
| 14 | `v=$(codex_run_exec x)` | 2 | コマンド置換内の実行は検出維持 |
| 15 | `true && codex_run_exec x` | 2 | `&&` 後の実行は検出維持 |
| 16 | `cat out.txt \| codex_strip_ansi` | 2 | パイプ先の実行は検出維持 |
| 17 | 複数行コマンド（1行目 `echo start`、2行目 `codex_run_exec x`） | 2 | 行頭アンカーが各行に効く |

ケース 17 は `printf 'echo start\ncodex_run_exec x'` のような複数行文字列を `run_hook` に渡して構成する。

**Verify**: `bash hooks/test-enforce-skill-usage.sh` → 17 ケース全 pass、exit 0

### Step 3: docs/bash-usage.md を更新する

- 「## Detection Patterns」の表の 1 行目（`\bcodex_[A-Za-z0-9_]+\b` の行）を新パターンに差し替え、Description を「Helper function calls **at execution position** (line start, after `;` `&` `|`, inside `$(...)` or backticks)」に、Limitation を「Mentions in argument text (commit messages, PR bodies, grep patterns) are allowed」に更新。
- 「### Known Limitations」に追記:
  - ヒアドキュメント内で行頭に関数名が来るテキストは誤検知しうる
  - `HELPERS=` パターンはメッセージテキスト内でも一致しうる（実害報告なしのため現状維持）
  - `env codex_x` や `bash -c 'codex_x ...'` のような間接実行は検出されない（fail-open 設計として許容）

**Verify**: 表とLimitations に上記が反映されていること（`grep -n 'execution position' docs/bash-usage.md` がヒット）

### Step 4: 全ゲート + バージョン更新

両 version ファイルを現行値から +1 のパッチバージョンに更新。

**Verify**:
- `bash hooks/test-enforce-skill-usage.sh` → 17 ケース pass
- `bash scripts/test-helpers.sh` → 0 failed
- `bash scripts/lint-plugin.sh` → PASS（version 同期チェック含む）
- `shellcheck --source-path=SCRIPTDIR -x hooks/*.sh` → exit 0

## Test plan

Step 2 の表が本体。ポイントは「言及 3 形状（ケース 11–13）が許可に変わり、実行 4 形状（ケース 2, 14–16）+ 複数行（17）が引き続きブロックされる」こと。既存ケース 1–10 は無変更で pass し続けること（ケース 2 `codex_run_exec prompt.txt` は行頭実行なので新パターンでも検出される）。

## Done criteria

- [ ] `bash hooks/test-enforce-skill-usage.sh` → 17 ケース以上すべて pass、exit 0
- [ ] ケース 11 の期待値が 0（言及許可）に反転している
- [ ] ケース 14–16（実行位置での検出維持）が含まれている
- [ ] `bash scripts/test-helpers.sh` → 0 failed
- [ ] `bash scripts/lint-plugin.sh` → PASS
- [ ] `shellcheck --source-path=SCRIPTDIR -x hooks/*.sh` → exit 0
- [ ] `docs/bash-usage.md` の Detection Patterns 表が新パターンと一致
- [ ] 2つの version ファイルが同一の新バージョン
- [ ] `plans/README.md` のステータス行を更新

## STOP conditions

- Step 1 の置換後、ケース 1–10 のいずれかが fail する場合（新パターンが既存挙動を壊している — 特にケース 2 が fail したら位置アンカーの書き方が誤り）。
- ケース 13 が exit 2 になる場合（コマンド文字列が 22 行目以外のパターンに一致している可能性。どのパターン行に一致したかを特定して報告。他パターン行の変更は本プランのスコープ外）。
- grep の ERE で `(^|[;&|]|\$\(|`)` がエラーになる場合（バッククォートのエスケープ問題等）。シェルクォートを変えて 2 回まで試行し、解消しなければ実エラーとともに STOP。

## Maintenance notes

- このフックは**セキュリティ境界ではなく LLM 誘導**。検出漏れ（`env codex_x` 等の間接実行）は設計上許容されるトレードオフであり、漏れを塞ぐためにパターンを再び広げると今回の誤検知が再発する。広げる変更には実害の証拠を要求すること。
- レビューで見るべき点: ケース 2 と 14–16 が本当に新パターンで検出されること（位置アンカーの正しさ）、docs の表とコードのパターンが一字一句一致していること。
- 将来 `HELPERS=` パターンの誤検知が実際に観測されたら、同じ位置アンカー手法（行頭 or 区切り文字後の代入のみ検出）で対応する。
