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

### TUI 出力形式

Codex CLI は **改行文字（`\n`）を含まない TUI 形式**で出力する。

- 画面更新は ANSI カーソル制御シーケンス（例: `\033[32;3H`）を使用
- `while read -r line` のような行単位読み取りは永遠にブロックされる
- ストリーム処理には `grep -qF` など、改行に依存しない方法を使用すること

```sh
# NG: 改行がないため永遠に待機
while IFS= read -r line; do
  echo "$line" | grep -qF "$MARKER" && break
done

# OK: ストリーム全体を検索
if grep -qF "$MARKER"; then
  # マーカー検出
fi
```

### マーカー形式

完了検出には `<<RESPONSE_END_xxx>>` 形式のユニークマーカーを使用:

```
<<RESPONSE_END_1770044801-429>>
```

### 完了検出方式

Codex の応答完了はポーリング方式で検出する:
- マーカー検出: `<<RESPONSE_END_xxx>>` の出現を監視
- アイドル検出: 出力のハッシュが一定時間変化しないことで完了を推定
- `codex_wait_completion()` がこれらを統合的に処理

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

### 詳細ドキュメント

Bash 使用ルールの詳細（スキルコンテキスト検出の仕組み、検出パターン、制限事項、トラブルシューティング）については、以下を参照してください:

**→ [docs/bash-usage.md](docs/bash-usage.md)**

> **Note**: `hooks/enforce-skill-usage.md` の PreToolUse フックがこのルールを強制します。
> 新しいコマンドを作成する場合は、`export CODEX_SKILL_CONTEXT=1` を Bash ブロックの先頭に追加してください。

## ヘルパースクリプトの管理

`scripts/codex-helpers.sh` には、コマンド間で共有されるbash関数が定義されています。

### 使用方法

各コマンドのbashブロックで以下のようにsourceします:

```bash
HELPERS="${CLAUDE_PLUGIN_ROOT:-$(pwd)}/scripts/codex-helpers.sh"
[ -f "$HELPERS" ] && source "$HELPERS"
```

> **注意:** `${CLAUDE_PLUGIN_ROOT}` はClaude Codeのコマンドmarkdown内では動作しない既知のバグがあります（[#9354](https://github.com/anthropics/claude-code/issues/9354)）。そのため `$(pwd)` へのフォールバックを使用しています。

### 関数の追加・変更

新しい共通関数を追加する場合:

1. `scripts/codex-helpers.sh` に関数を追加
2. 関数名は `codex_` プレフィックスを使用（例: `codex_new_function()`）

### 現在の関数一覧

コア関数（すべてのコマンドで必須）:

- `codex_ensure_tmp_dir()` - 一時ディレクトリの確保（絶対パスを返す）
- `codex_find_pane()` - Codexペイン検出（保存ID + 自動検出）
- `codex_verify_pane()` - ペインのヘルスチェック（存在・セッション・プロセス確認）
- `codex_get_or_create_pane()` - ペインの取得または作成（統合エントリポイント）
- `codex_send_prompt_file()` - ファイル参照によるプロンプト送信
- `codex_send_prompt_chunked()` - 分割送信によるプロンプト送信（長いプロンプト向け）
- `codex_wait_completion()` - 完了待機（ポーリング方式）
- `codex_capture_output()` - 出力キャプチャ

ユーティリティ関数:

- `codex_hash_content()` - クロスプラットフォームハッシュ計算
- `codex_check_tmux()` - tmuxセッション確認
- `codex_get_language_directive()` - 言語指示生成（多言語対応）
- `codex_extract_metadata()` - レスポンスからメタデータ抽出
- `codex_get_status()` / `codex_get_verdict()` - メタデータフィールド取得
