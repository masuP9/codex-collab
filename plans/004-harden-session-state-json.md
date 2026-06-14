# Plan 004: セッション状態の手書き JSON 処理と ANSI 除去を堅牢化する

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat a54f1d9..HEAD -- scripts/codex-helpers.sh scripts/test-helpers.sh`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED（状態の保存/読込はワークフロー継続の生命線。テストがゲート）
- **Depends on**: none（Plan 001 の後に実行すると変更が shellcheck される。推奨順は 001 → 004）
- **Category**: bug
- **Planned at**: commit `a54f1d9`, 2026-06-12（初版は `f5abf51`/2026-06-11。Plan 001 の shellcheck アノテーション追加による行番号ずれを反映して refresh 済み。対象関数のロジック自体は初版調査時から無変更）

## Why this matters

セッション状態（`tmp/codex-session-{task_id}.json`）は MCP の threadId・ワークフロー種別を保持し、compaction 後の復旧や claude-leads の Thread B/C 切り替えに使われる。この JSON の生成と解析はすべて手書きの sed/grep で行われており、値に引用符・タブ・制御文字が入ると**静かに壊れる**経路が複数ある。現状の実運用値（threadId は UUID、sandbox/workflow は固定語彙）では顕在化しにくいが、壊れたときの症状は「スレッドが復元できず会話コンテキストが消える」という追跡しにくいもので、修正コストに対して保険価値が高い。あわせて ANSI 除去が CSI シーケンスしか対応していない点も直す（codex CLI の出力には OSC 系が混ざりうる）。

具体的な既知の欠陥（すべてコード精読で確認済み）:

1. `codex_json_escape` が制御文字（タブ、CR 等）をエスケープしない → 不正な JSON を生成しうる。
2. 値の読み出し regex `[^"]*` がエスケープ済み引用符 `\"` を扱えない → 値の途中で切れ、`codex_save_thread` の再構築時に末尾に孤立バックスラッシュが残って JSON 全体が壊れる。
3. `codex_load_thread` / `codex_save_thread` のスレッド名マッチが「行にその文字列を含むか」だけで、**値**にスレッド名が含まれる場合に誤った行を拾う/落とす。
4. `codex_strip_ansi` は CSI（`ESC[...m` 等）のみ対応。OSC（`ESC]...BEL`）等は素通し。

## Current state

すべて `scripts/codex-helpers.sh`（742 行、2026-06-12 時点）:

`codex_json_escape`（468-470行）:

```bash
codex_json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' '
}
```

読み出しパターン（663-668 行 `codex_load_session_state`。592-595 行 `codex_save_thread`、636 行 `codex_load_thread` にも同形。SESSION_SANDBOX / SESSION_WORKFLOW の行間には Plan 001 で入った `# shellcheck disable=SC2034` コメントが挟まっている — 編集時はコメントを保持すること）:

```bash
SESSION_MODE=$(grep '"mode"' "$state_file" | sed 's/.*: *"\([^"]*\)".*/\1/' | head -1 || true)
```

スレッド名マッチ（636 行 `codex_load_thread`、574 行 `codex_save_thread` のフィルタ）:

```bash
grep "\"${esc_name}\"" "$state_file" | sed 's/.*: *"\([^"]*\)".*/\1/' | head -1 || true
# save_thread 側:
filtered=$(echo "$existing_threads" | grep -v "\"${esc_name}\"" || true)
```

`codex_strip_ansi`(137-143 行。直前 136 行に Plan 001 の `# shellcheck disable=SC2120` コメントあり — 保持すること):

```bash
codex_strip_ansi() {
  if [ $# -gt 0 ]; then
    printf '%s' "$1" | sed $'s/\033\\[[0-9;]*[a-zA-Z]//g'
  else
    sed $'s/\033\\[[0-9;]*[a-zA-Z]//g'
  fi
}
```

**守るべきリポジトリ制約**:
- `scripts/codex-helpers.sh:661` のコメント「no jq dependency」のとおり、ヘルパーは jq に依存しない。この方針を維持する（jq 導入による解決は採らない）。
- ANSI の sed は `$'...'` クォートが必須（`\x1b` ヘックスは macOS sed で「Unmatched ( or \\(」を起こす既知問題 — CLAUDE.md 参照）。新パターンも同じクォート方式で書く。
- macOS（BSD sed）互換を保つ: `sed -E` は両対応、`sed -i` の引数差異などに注意。

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| テスト | `bash scripts/test-helpers.sh` | 既存 89 + 新規 N が全 pass、0 failed |
| shellcheck（Plan 001 導入済みの場合） | `shellcheck scripts/codex-helpers.sh` | exit 0 |

## Scope

**In scope**:
- `scripts/codex-helpers.sh` — 上記 4 関数群（`codex_json_escape`, `codex_save_session_state`, `codex_save_thread`, `codex_load_thread`, `codex_load_session_state`, `codex_strip_ansi`）のみ
- `scripts/test-helpers.sh` — テスト追加
- `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` — バージョン更新

**Out of scope**:
- 状態ファイルのスキーマ変更（キー名・構造は現状維持。commands/*.md が `codex_save_thread "$TASK_ID" "threadB" ...` 等の形で呼んでいるため、関数シグネチャも変えない）
- `commands/*.md`（呼び出し側は無変更で恩恵を受ける設計にする）
- jq への移行・依存追加
- `codex_extract_metadata` / verdict 系（別系統。問題は確認されていない）

## Git workflow

- Branch: `fix/session-state-hardening`
- conventional commits 形式（例: `fix: harden JSON session state escaping and parsing (vX.Y.Z)`）
- push / PR 作成はオペレーターの指示があるまで行わない。

## Steps

### Step 1: 先に失敗するテストを書く（characterization）

`scripts/test-helpers.sh` に以下のケースを追加する（既存のセッション状態テスト群の隣に置き、既存の pass/fail ハーネスと書式を踏襲）:

1. `codex_json_escape "$(printf 'a\tb')"` の出力に生タブが含まれない
2. `codex_json_escape "$(printf 'a\rb')"` の出力に CR が含まれない
3. workflow 値に `"` を含めて `codex_save_session_state` → `codex_load_session_state` がexit 0 で完走し、`SESSION_MODE` が正しく読める（ファイルが壊れていない）
4. 値に引用符を含む状態で `codex_save_thread` を実行しても、その後の `codex_load_session_state` が成功する（再構築による破損がない）
5. threads に `threadB` と、**値の中に文字列 `threadB` を含む** `threadC` を保存 → `codex_load_thread "$tid" "threadC"` が threadC の値を返し、`codex_save_thread` で threadB を更新しても threadC が消えない
6. `codex_strip_ansi` が OSC シーケンス（`$'\033]0;title\007'` を埋め込んだ文字列）を除去する

この時点でケース 1,2,5,6（および環境により 3,4）が **fail する**ことを確認する。

**Verify**: `bash scripts/test-helpers.sh` → 新規ケースが fail として報告される（既存 89 は pass のまま）

### Step 2: `codex_json_escape` を制御文字対応にする

置き換え（タブは `\t` にエスケープ、CR は除去、その他 C0 制御文字も除去。改行→スペースの既存挙動は維持）:

```bash
codex_json_escape() {
  printf '%s' "$1" \
    | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' \
    | tr '\n' ' ' \
    | tr -d '\000-\010\013-\037'
}
```

注意: `tr -d` の範囲から `\011`（タブ）は sed で先に変換済み、`\012`（改行）は tr で変換済みなので、残る制御文字のみ削除される。

**Verify**: テストケース 1, 2 が pass

### Step 3: 値読み出しの sed をエスケープ対応にする

`codex_load_session_state`（663-668 行）、`codex_save_thread` の再読込（592-595 行）、`codex_load_thread`（636 行）の `sed 's/.*: *"\([^"]*\)".*/\1/'` をすべて次に置換:

```bash
sed -E 's/.*: *"((\\.|[^"\\])*)".*/\1/'
```

（エスケープシーケンス `\.` を 1 単位として扱い、エスケープ済み引用符で途切れない。GNU/BSD 両 sed の `-E` で動作する。）

**Verify**: テストケース 3, 4 が pass

### Step 4: スレッド名マッチをキー位置にアンカーする

- `codex_load_thread`（636 行）: `grep "\"${esc_name}\""` → `grep -F "\"${esc_name}\":"`（fixed-string + キーのコロンまで含めて、値との衝突と regex 解釈を同時に排除）
- `codex_save_thread`（574 行）: `grep -v "\"${esc_name}\""` → `grep -vF "\"${esc_name}\":"`

**Verify**: テストケース 5 が pass

### Step 5: `codex_strip_ansi` を OSC 対応にする

両分岐の sed を、CSI に加えて OSC（BEL 終端・ESC\ 終端）を除去する形に拡張する。`$'...'` クォートを維持すること:

```bash
sed $'s/\033\\[[0-9;]*[a-zA-Z]//g; s/\033][^\007\033]*\007//g; s/\033][^\007\033]*\033\\\\//g'
```

**Verify**: テストケース 6 が pass

### Step 6: 全体回帰とバージョン更新

**Verify**:
- `bash scripts/test-helpers.sh` → 全 pass（89 + 新規、0 failed）
- `bash skills/claude-collab/scripts/test-claude-helpers.sh` → pass
- （Plan 001 済みなら）`shellcheck scripts/codex-helpers.sh scripts/test-helpers.sh` → exit 0
- 両 version ファイルをパッチバージョンアップし、`grep '"version"' .claude-plugin/*.json` で一致確認

## Test plan

Step 1 の 6 ケースが本体。既存のセッション状態テスト（save/load round-trip、task_id 分離、named threads、threads preservation、malformed state file recovery）を回帰ゲートとして全部通すこと。テストの構造・命名・assert 方法は `scripts/test-helpers.sh` 内の既存セッション状態テストを手本にする。

## Done criteria

- [ ] `bash scripts/test-helpers.sh` → 0 failed、新規 6 ケース以上を含む
- [ ] `bash skills/claude-collab/scripts/test-claude-helpers.sh` → pass
- [ ] `grep -n 'jq' scripts/codex-helpers.sh` がヒットしない（no-jq 制約維持）
- [ ] `git diff --stat` の変更ファイルが In scope のみ
- [ ] 2つの version ファイルが同一の新バージョン
- [ ] `plans/README.md` のステータス行を更新

## STOP conditions

- Step 3 の `sed -E` パターンが手元の sed で動かない場合（GNU 拡張に依存していたと判明した場合）。代替実装を即興で書かず、失敗する入力例とともに STOP。
- 既存 89 テストのいずれかが落ち、2 回の修正試行で解消しない場合。
- 修正の過程で `commands/*.md` 側の変更が必要に見えた場合（シグネチャ互換を壊した兆候）。
- `codex_save_session_state` の threads ブロック温存ロジック（512 行の `sed -n '/"threads":/,/}/...'`、`codex_save_thread` 側は 567 行）にまで手を入れる必要が出た場合。この部分は値に `}` 単独行が含まれない前提で動いており、本プランの範囲外。壊れるケースを見つけたら報告のみ。

## Maintenance notes

- 値のエスケープ仕様が「タブ→`\t`、改行→スペース、CR/制御文字→除去」になる。読み出し側はアンエスケープしない（threadId 等の実用値には影響しない設計）。将来、値を完全に往復させたい場合は jq 導入の議論からやり直すこと。
- レビューで見るべき点: sed パターンの BSD 互換性、テストケース 5（名前と値の衝突）が本当に修正前に fail することの確認。
- 状態ファイルを並行プロセスが同時更新するケース（ロックなし）は未対応のまま。task_id 分離で実用上回避されているため意図的に見送り。
