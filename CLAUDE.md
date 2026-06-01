# CLAUDE.md

このファイルはClaude Codeがこのリポジトリで作業する際のガイダンスを提供します。

## Codex Leaf Reviewer Mode

Codex 側の `claude-collab` ラッパーから呼び出された場合、CLI の system prompt に `CLAUDE_COLLAB_CALLER=codex` 相当の leaf reviewer 指示が含まれます。

その場合:

- この `CLAUDE.md` はプロジェクト構造、リリースルール、実装上の制約を理解するために使用する
- Codex MCP、`codex exec`、`codex review`、Codex と一緒に作業するためのスキル、スラッシュコマンドを呼び出さない
- 新しく Codex と一緒に作業を始めず、既存セッションも継続しない
- ファイル変更、PR 作成、Bash 委任を行わない
- 依頼されたレビューまたは助言だけを返して終了する

## リリースワークフロー

### バージョン更新

PRを作成する前に、変更内容に応じて以下の **両方のファイル** のバージョンを更新すること。

- `.claude-plugin/plugin.json`
- `.claude-plugin/marketplace.json`

**バージョニングルール:**

- **パッチ (0.0.x)**: バグ修正、ドキュメント修正、小さな改善
- **マイナー (0.x.0)**: 新機能追加、後方互換性のある変更
- **メジャー (x.0.0)**: 破壊的変更

```json
// plugin.json
{
  "version": "0.3.0"  // ← 変更内容に応じて更新
}

// marketplace.json (plugins[0].version も同じ値に更新)
{
  "plugins": [
    {
      "version": "0.3.0"  // ← plugin.json と同じ値
    }
  ]
}
```

## Codex 通信の仕様

OpenAI Codex と連携する際に知っておくべき仕様。**MCP primary + Bash fallback** のデュアルモード。

### Codex MCP Tools（ステートフル、推奨）

Codex MCP サーバー (`codex mcp-server`) 経由でステートフルなセッション管理が可能。

```
# 新規セッション開始
mcp__codex__codex(prompt: "...", sandbox: "read-only")
→ Returns: response + threadId

# 同一スレッドで継続（会話コンテキスト自動保持）
mcp__codex__codex-reply(threadId: "...", prompt: "...")
→ Returns: response
```

- ステートフル: threadId で会話コンテキスト保持（multi-turn exchange で履歴再構築不要）
- クリーンテキスト: ANSI 除去不要
- ファイル I/O 不要: prompt/output の tmp ファイル不要
- MCP 未設定時は自動的に Bash fallback に切り替え

### codex exec（ステートレス実行、Bash fallback）

MCP が利用できない場合のフォールバック。プロンプトを stdin から受け取り、結果を stdout に出力してブロッキング終了する。

```sh
# 基本パターン
codex exec -s read-only - < prompt.txt

# モデル指定
codex exec -s read-only -m o4-mini - < prompt.txt
```

- 各呼び出しはステートレス（会話コンテキストは保持されない）
- 出力に ANSI エスケープコードが含まれる場合があるため `codex_strip_ansi()` で除去
- `codex_run_exec()` がファイル入出力、ANSI 除去、exit code ハンドリングを統合処理

### codex review（コードレビュー、Bash fallback）

`codex review --uncommitted` はステージ済み/未コミットの差分を自動収集してレビューを行う専用サブコマンド。MCP では利用不可（diff を prompt に埋め込む）。

```sh
# 基本パターン
codex review --uncommitted

# カスタムプロンプト付き
codex review --uncommitted "セキュリティ脆弱性に注目してレビュー"
```

- レビューフェーズでは `codex review` を第一選択、失敗時は `codex exec` にフォールバック
- `codex_run_review()` が ANSI 除去、出力保存、exit code ハンドリング、モデル指定 retry を統合処理
- `codex_infer_verdict()` でレスポンスから verdict を推定（メタデータ → `[P1]-[P4]` → findings なし pass）

## プロジェクト構造

- `commands/` - `/collab` などのスラッシュコマンド
- `scripts/` - 共通ヘルパースクリプト
- `skills/codex-collab/` - スキル定義とリファレンス
- `hooks/` - PreToolUse などのフック
- `docs/` - プラグインドキュメント（Bash使用ルールなど）
- `.claude-plugin/plugin.json` - プラグインメタデータ（バージョン含む）
- `.claude-plugin/marketplace.json` - マーケットプレイス公開用メタデータ（バージョン含む）
- `.gitignore` - Codex一時ファイルの除外パターン

## Bash 使用ルール

codex-collab のヘルパー関数を直接 Bash で実行すると、承認プロンプトが表示されることがあります。
**必ずスキル経由で実行してください。**

### クイックリファレンス

| 目的 | 使用するスキル |
|------|---------------|
| 協調タスク開始 | `/codex-collab [task]` |
| 協調計画作成 | `/collab-planning [idea]` |
| 問題調査 | `/strong-inference [problem]` |
| 設計検証 | `/devils-advocate [proposal]` |

### 詳細ドキュメント

Bash 使用ルールの詳細（スキルコンテキスト検出の仕組み、検出パターン、制限事項、トラブルシューティング）については、以下を参照してください:

**→ [docs/bash-usage.md](docs/bash-usage.md)**

> **Note**: `hooks/enforce-skill-usage.sh` の PreToolUse フック（command型）がこのルールを強制します。
> 新しいコマンドを作成する場合は、`export CODEX_SKILL_CONTEXT=1` を Bash ブロックの先頭に追加してください。

## ヘルパースクリプトの管理

`scripts/codex-helpers.sh` には、コマンド間で共有されるbash関数が定義されています。

### 使用方法

各コマンドのbashブロックで以下のようにsourceします:

```bash
# Mark skill context for PreToolUse hook detection
export CODEX_SKILL_CONTEXT=1

# Robust helper loading with fallback chain
HELPERS=""
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh" ]; then
  HELPERS="${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh"
elif [ -d ~/.claude/plugins/cache/codex-collab ]; then
  HELPERS=$(ls -td ~/.claude/plugins/cache/codex-collab/codex-collab/*/scripts/codex-helpers.sh 2>/dev/null | head -1)
fi
[ -z "$HELPERS" ] || [ ! -f "$HELPERS" ] && HELPERS="$(pwd)/scripts/codex-helpers.sh"
[ -f "$HELPERS" ] && source "$HELPERS"
```

> **注意:** `${CLAUDE_PLUGIN_ROOT}` はClaude Codeのコマンドmarkdown内では動作しない既知のバグがあります（[#9354](https://github.com/anthropics/claude-code/issues/9354)）。上記のフォールバックチェーンで `~/.claude/plugins/cache` を探索するようにしています。

### 関数の追加・変更

新しい共通関数を追加する場合:

1. `scripts/codex-helpers.sh` に関数を追加
2. 関数名は `codex_` プレフィックスを使用（例: `codex_new_function()`）

### 現在の関数一覧

コア関数（Bash fallback 用の Codex 実行）:

- `codex_run_exec()` - codex exec のラッパー（stdin パイプ、ANSI 除去、出力保存、exit code ハンドリング）
- `codex_run_review()` - codex review --uncommitted のラッパー（ANSI 除去、出力保存、モデル retry、exit code ハンドリング）
- `codex_build_exec_command()` - codex exec コマンド文字列の構築
- `codex_write_prompt()` - プロンプトを一時ファイルに書き出し
- `codex_strip_ansi()` - ANSI エスケープコード除去

レビュー解析（Bash fallback 用）:

- `codex_infer_verdict()` - レビューレスポンスから verdict を推定（メタデータ → [P1]-[P4] → findings なし pass）
- `codex_extract_review_findings()` - レビューレスポンスから findings を抽出

セッション状態管理（MCP/Bash デュアルモード用）:

- `codex_save_session_state()` - セッション状態を JSON ファイルに保存（task_id 単位で分離、値はエスケープ済み）
- `codex_load_session_state()` - セッション状態を読み込み（MODE, THREAD_ID 等をグローバル変数にセット）
- `codex_save_thread()` - 名前付きスレッドを保存（claude-leads の Thread B/C 用）
- `codex_load_thread()` - 名前付きスレッドを読み込み
- `codex_sanitize_task_id()` - task_id のファイル名安全化（英数字・ハイフン・アンダースコアのみ）
- `codex_json_escape()` - JSON 値のエスケープ（引用符・バックスラッシュ・改行）
- `codex_diff_tier()` - diff のサイズに応じてティア判定（small/medium/large）

ユーティリティ関数:

- `codex_ensure_tmp_dir()` - 一時ディレクトリの確保（絶対パスを返す）
- `codex_tmp_path()` - 一時ディレクトリ内のファイルパス取得
- `codex_hash_content()` - クロスプラットフォームハッシュ計算
- `codex_generate_signal()` - ユニークID生成
- `codex_get_language_directive()` - 言語指示生成（多言語対応）
- `codex_debug()` - デバッグログ出力

メタデータ抽出:

- `codex_extract_metadata()` - レスポンスからメタデータ抽出
- `codex_get_field()` - メタデータフィールド取得
- `codex_get_status()` / `codex_get_verdict()` - メタデータフィールド取得
