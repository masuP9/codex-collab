# CLAUDE.md

このファイルはClaude Codeがこのリポジトリで作業する際のガイダンスを提供します。

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

## Codex CLI の仕様

OpenAI Codex CLI と連携する際に知っておくべき仕様:

### codex exec（ステートレス実行）

Codex CLI との通信には `codex exec` を使用する。プロンプトを stdin から受け取り、結果を stdout に出力してブロッキング終了する。

```sh
# 基本パターン
cat prompt.txt | codex exec -s read-only -

# モデル指定
cat prompt.txt | codex exec -s read-only -m o4-mini -
```

- 各呼び出しはステートレス（会話コンテキストは保持されない）
- 出力に ANSI エスケープコードが含まれる場合があるため `codex_strip_ansi()` で除去
- `codex_run_exec()` がファイル入出力、ANSI 除去、exit code ハンドリングを統合処理

## プロジェクト構造

- `commands/` - `/collab` などのスラッシュコマンド
- `scripts/` - 共通ヘルパースクリプト
- `skills/codex-collaboration/` - スキル定義とリファレンス
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
| 協調タスク開始 | `/collab-codex [task]` |
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

コア関数（Codex 実行）:

- `codex_run_exec()` - codex exec のラッパー（stdin パイプ、ANSI 除去、出力保存、exit code ハンドリング）
- `codex_build_exec_command()` - codex exec コマンド文字列の構築
- `codex_write_prompt()` - プロンプトを一時ファイルに書き出し
- `codex_strip_ansi()` - ANSI エスケープコード除去

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
