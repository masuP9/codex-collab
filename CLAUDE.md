# CLAUDE.md

このファイルはClaude Codeがこのリポジトリで作業する際のガイダンスを提供します。

## リリースワークフロー

### バージョン更新

PRを作成する前に、変更内容に応じて `.claude-plugin/plugin.json` のバージョンを更新すること。

- **パッチ (0.0.x)**: バグ修正、ドキュメント修正、小さな改善
- **マイナー (0.x.0)**: 新機能追加、後方互換性のある変更
- **メジャー (x.0.0)**: 破壊的変更

```json
{
  "version": "0.3.0"  // ← 変更内容に応じて更新
}
```

## プロジェクト構造

- `commands/` - `/collab` などのスラッシュコマンド
- `scripts/` - 共通ヘルパースクリプト
- `skills/codex-collaboration/` - スキル定義とリファレンス
- `.claude-plugin/plugin.json` - プラグインメタデータ（バージョン含む）
- `.gitignore` - Codex一時ファイルの除外パターン

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
- `codex_send_prompt()` - プロンプト送信
- `codex_send_prompt_file()` - ファイル参照によるプロンプト送信（長いプロンプト向け）
- `codex_wait_completion()` - 完了待機
- `codex_capture_output()` - 出力キャプチャ
- `codex_check_tmux()` - tmuxセッション確認
- `codex_generate_signal()` - ユニークシグナル生成
- `codex_acquire_lock()` - 排他ロック取得（競合防止）
- `codex_release_lock()` - ロック解放
