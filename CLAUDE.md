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

### ファイルベース応答

長い応答はファイルに書き込まれる:
- 応答ファイル: `tmp/codex-response-*.md`
- プロンプト内でファイルパスを指定し、Codex に書き込ませる

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
| 新しい協調タスク開始 | `/collab-codex [task]` |
| 既存ペインへのプロンプト送信 | `/collab-codex-attach [prompt]` |
| ステータス確認 | `/collab-codex-attach status` |

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
3. 各コマンドでインラインのフォールバック実装も追加（ヘルパーが利用できない場合に備えて）

### 現在の関数一覧

- `codex_hash_content()` - クロスプラットフォームハッシュ計算
- `codex_find_pane()` - Codexペイン検出
- `codex_verify_pane()` - ペインの有効性検証
- `codex_send_prompt()` - プロンプト送信（paste-buffer方式）
- `codex_send_prompt_file()` - ファイル参照によるプロンプト送信（長いプロンプト向け）
- `codex_send_prompt_chunked()` - 分割送信によるプロンプト送信（長いプロンプトの安定送信向け）
- `codex_send_chunked()` - 低レベルの分割送信（テキストのみ、Enterなし）
- `codex_wait_completion()` - 完了待機
- `codex_capture_output()` - 出力キャプチャ
- `codex_check_tmux()` - tmuxセッション確認
- `codex_generate_signal()` - ユニークシグナル生成
- `codex_acquire_lock()` - 排他ロック取得（競合防止）
- `codex_release_lock()` - ロック解放
