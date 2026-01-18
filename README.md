# codex-collab

Claude Code と OpenAI Codex CLI を協調させてタスクを実行するプラグイン。

## 概要

このプラグインは、Claude Code と Codex の強みを組み合わせた協調ワークフローを提供します。

**基本パターン（レビュー型）:**
- **Codex**: 計画作成・コードレビュー
- **Claude Code**: 実装

## インストール

```bash
# マーケットプレイスを追加
/plugin marketplace add https://github.com/masuP9/codex-collab

# プラグインをインストール
/plugin install codex-collab@codex-collab
```

## 前提条件

- OpenAI Codex CLI (`codex`) がインストールされていること
- 環境変数 `OPENAI_API_KEY` が設定されていること
- WSL環境: Windows Terminal (`wt.exe`) が利用可能であること（リアルタイム出力確認用）
- オプション: tmuxセッション内で作業している場合、フォーカスを奪わずにCodexを実行可能
- オプション: `jq` (セッション状態管理に使用。未インストールの場合は毎回新規セッションとして扱う)

## プロジェクト構造

```
codex-collab/
├── .claude-plugin/
│   └── plugin.json        # プラグインメタデータ
├── commands/
│   ├── collab.md          # /collab コマンド
│   └── collab-attach.md   # /collab-attach コマンド
├── scripts/
│   └── codex-helpers.sh   # 共通ヘルパー関数
└── skills/
    └── codex-collaboration/
        └── references/     # プロトコル定義
```

### ヘルパースクリプト

`scripts/codex-helpers.sh` には、コマンド間で共有される関数が定義されています:

**基本関数:**
- `codex_hash_content()` - クロスプラットフォームハッシュ計算
- `codex_find_pane()` - Codexペイン検出（保存ID + 自動検出）
- `codex_verify_pane()` - ペインの有効性検証
- `codex_send_prompt()` - tmux paste-bufferでのプロンプト送信
- `codex_send_prompt_file()` - ファイル参照によるプロンプト送信（長いプロンプト向け）
- `codex_clear_input()` - ペイン入力欄のクリア
- `codex_wait_completion()` - マーカー + アイドル検出による完了待機
- `codex_capture_output()` - ペイン出力のキャプチャ
- `codex_check_tmux()` - tmuxセッション確認

**軽量メタデータ抽出:**
- `codex_extract_metadata()` - 応答末尾のYAMLブロックを抽出
- `codex_get_status()` - status フィールド取得（continue/stop）
- `codex_get_verdict()` - verdict フィールド取得（pass/conditional/fail）
- `codex_get_list()` - リストフィールド取得
- `codex_parse_response()` - 応答を本文とメタデータに分離

**自動承認（セキュア）:**
- `codex_get_pending_command()` - アクティブな承認ダイアログを検出
- `codex_approve_if_matches()` - パターンマッチで承認
- `codex_approve_response_commands()` - set-buffer + wait-for を自動承認

**セッション管理:**
- `codex_collab_session_start()` - collabセッションを作成/アタッチ
- `codex_collab_session_exists()` - セッション存在確認
- `codex_collab_session_info()` - セッション情報表示
- `codex_collab_session_kill()` - セッション終了

各コマンドは自動的にヘルパーをsourceし、利用できない場合はインラインのフォールバック実装を使用します。

## 使い方

### `/collab` コマンド

協調ワークフローを開始します。

```
/collab 新しい認証機能を実装して
```

**自動検出機能 (tmuxモード):**
- tmuxセッション内で実行時、`tmp/codex-pane-id`がなくても既存のCodexペインを自動検出
- 検出されたペインは`tmp/codex-pane-id`に保存され、attached modeで使用
- 複数のCodexペインがある場合は最初のペインを使用（警告を表示）
- Codexペインが見つからない場合は従来通り新規`codex exec`を起動

### `/collab-attach` コマンド

既存のCodexペインに接続して、永続的なコラボレーションを行います。

```
# まず別ペインでCodexを起動（インタラクティブモード）
tmux split-window -h 'codex'

# 既存のCodexペインにプロンプトを送信
/collab-attach この機能の設計を考えて

# ステータス確認
/collab-attach status

# 出力をキャプチャ
/collab-attach capture

# ペインIDをクリア（別のCodexペインに接続したい場合）
/collab-attach detach
```

**特徴:**
- tmuxセッション内で動作（`$TMUX`が必要）
- 既存のCodexセッションを維持（コンテキストが保持される）
- ペインIDは`tmp/codex-pane-id`に保存され、次回自動検出
- **セッション状態管理**: 初回は完全コンテキスト、継続時は軽量な`## Update`形式で送信（トークン節約）
- セッションは30分でタイムアウト（`tmp/codex-session-state`で管理）

### プロジェクト内ソケットでの双方向通信（高度な使い方）

`workspace-write` sandboxでCodexからClaude Codeへの通信を可能にするため、プロジェクト内にtmuxソケットを作成できます。

```bash
# ヘルパーをsource
source scripts/codex-helpers.sh

# collabセッションを作成（Codex自動起動）
codex_collab_session_start --start-codex --attach

# または手動でセッション作成
tmux -S ./collab.sock new-session -s collab
```

**メリット:**
- `workspace-write` sandboxでも双方向通信が可能
- ポーリング不要のイベントドリブン完了検知（`wait-for`）
- Codexの承認ダイアログを自動承認可能

**構成:**
```
./collab.sock (プロジェクト内tmuxソケット)
├── collab:1.0 - Claude Code (左ペイン)
└── collab:1.1 - Codex (右ペイン)
```

詳細は `docs/bidirectional-communication-design.md` を参照してください。

### スキルの自動起動

以下のようなリクエストで自動的にスキルが有効になります:
- 「Codexと協調してタスクを実行したい」
- 「Codexにレビューを依頼して」
- 「Codexに計画を作成させたい」

## 設定

プロジェクト固有の設定は `.claude/codex-collab.local.md` に記述できます。

```markdown
---
model: o4-mini
sandbox: read-only
---

# プロジェクト固有の指示

このプロジェクトでは TypeScript を使用しています。
```

### 設定オプション

| オプション | デフォルト | 説明 |
|-----------|-----------|------|
| `model` | (Codexデフォルト) | 使用するモデル (o3, o4-mini等) |
| `sandbox` | `read-only` | サンドボックスモード (read-only, workspace-write, danger-full-access) |
| `launch.mode` | `auto` | 起動モード (auto, tmux, wt, inline)。autoはtmuxセッション内ならtmux、そうでなければwt→inline |
| `exchange.enabled` | `true` | Planning exchangeのグローバルキルスイッチ |
| `exchange.max_iterations` | `3` | Planning exchangeの最大ラウンド数 |
| `exchange.user_confirm` | `on_important` | ユーザー確認タイミング (never, always, on_important) |
| `exchange.history_mode` | `summarize` | 履歴管理方式: full=全履歴保持, summarize=最新2ラウンドのみ全文 |
| `review.enabled` | `true` | Review iterationの有効化 |
| `review.max_iterations` | `5` | Review iterationの最大ラウンド数（ゴールが明確なので多め） |
| `review.user_confirm` | `never` | レビュー時は自動でイテレーション |

### Launch Mode について

Codexの起動方法を選択できます:

| モード | 説明 | フォーカス奪取 | 完了検知 |
|--------|------|---------------|---------|
| `tmux` | 現在のペインを分割してCodexを実行（右側に表示） | なし | `tmux wait-for`（即時） |
| `wt` | Windows Terminalの新しいペインで実行 | あり | ファイルポーリング |
| `inline` | 現在のターミナルで実行（ブロッキング） | - | ファイルポーリング |
| `auto` | tmuxセッション内ならtmux、そうでなければwt→inline | 状況による | モードに依存 |

> **Note:** tmuxモードは現在のペインを水平分割し、右側でCodexを実行します。`tmux wait-for`によりCodex完了を即座に検知できます（ポーリング不要）。

### 設定の優先順位

```
コマンド引数 > プロジェクト設定 > グローバル設定 > 安全デフォルト
```

## ワークフロー

```
1. ユーザー: /collab "機能Xを実装して"
2. Claude Code: タスク分析・Codex向けプロンプト作成
3. Codex: 計画作成
4. Claude Code: 計画確認・実装
5. Codex: レビュー（Pass/Fail/Conditional）
6. Claude Code: 修正（必要に応じて）・完了報告
```

## 軽量メタデータプロトコル

Claude Code と Codex CLI 間の議論をサポートする軽量なメタデータ形式を採用しています。

### 設計思想

- **本文は自然言語のまま**: LLM の表現力を制限しない
- **メタデータは末尾に付加**: 応答の最後に YAML ブロックとして追加
- **フォールバック可能**: メタデータがなくても本文は読める

### メタデータ形式

応答の末尾に `---` で囲まれた YAML ブロックを付加：

```markdown
（自然言語の応答本文）

...議論や説明...

---
status: stop
verdict: conditional
open_questions:
  - 認証方式の選択
findings:
  - severity: medium
    message: 入力バリデーションが不足
---
```

### フィールド一覧

| フィールド | 型 | 説明 |
|-----------|-----|------|
| `status` | enum | `continue` / `stop` - 議論を続けるか終了するか |
| `verdict` | enum | `pass` / `conditional` / `fail` - レビュー判定 |
| `open_questions` | list | 未解決の質問 |
| `decisions` | list | 合意した決定事項 |
| `findings` | list | 発見事項（severity, message） |

### 使用例

**レビュー応答:**

```markdown
コードを確認しました。全体的に良い実装ですが、改善点があります。

1. `validate_input()` で空文字列のチェックが抜けています
2. エラーメッセージがハードコードされています

---
status: stop
verdict: conditional
findings:
  - severity: medium
    message: validate_input() で空文字列チェックが不足
  - severity: low
    message: エラーメッセージのハードコード
---
```

**議論応答（継続）:**

```markdown
認証方式について検討しました。JWT と Session の両方に利点がありますが...

いくつか確認したい点があります：
- ユーザー数の想定規模は？
- モバイルアプリからのアクセスは想定していますか？

---
status: continue
open_questions:
  - ユーザー規模の想定
  - モバイルアプリ対応の有無
decisions:
  - REST API で実装する
---
```

### 関連ファイル

詳細な仕様は `skills/codex-collaboration/references/` にあります：

- `lightweight-metadata.md` - 軽量メタデータプロトコル仕様
- `planning-prompt.md` - 計画依頼テンプレート
- `review-prompt.md` - レビュー依頼テンプレート
- `deprecated/` - 旧構造化プロトコル（参考用）

## ライセンス

MIT
