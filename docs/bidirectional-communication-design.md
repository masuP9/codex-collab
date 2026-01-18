# Claude Code ↔ Codex 双方向通信の設計検討

## 背景

現在の課題：
- tmux paste-buffer で長いプロンプト（400行程度）を送ると破損する
- 完了検出にポーリング（capture-pane + マーカー検出）を使っている → 非効率

理想の形：
- Claude Code ↔ Codex の双方向通信
- ポーリングではなくイベントドリブン

## 検討した方式

### 1. ハイブリッド方式（ファイルパス参照 + ファイルベース）✅ 実装済み

**概要:**
- 詳細な指示を `.codex-review-instructions.md` に書く
- 短いプロンプトだけ tmux で送信（ファイルパスを参照）
- Codex が自分でファイルを読んで処理

**結果:**
- ✅ 動作確認済み
- ✅ 長いプロンプトの破損問題を解決
- ❌ 完了検出は依然としてポーリング

**実装:**
- `codex_send_prompt_file()` 関数を `scripts/codex-helpers.sh` に追加

---

### 2. tmux send-keys による双方向通信（Codex → Claude）❌ sandbox制限

**概要:**
- Claude Code が自分のペインID（例: `%34`）を Codex に伝える
- Codex が処理完了後、`tmux send-keys -t %34` で Claude に通知

**試した結果:**
```
$ tmux list-panes
error connecting to /tmp/tmux-1001/default (Operation not permitted)
```

**原因:**
- tmux ソケット `/tmp/tmux-1001/default` はプロジェクト外
- `workspace-write` sandbox でもプロジェクト外へのアクセスは制限される
- `danger-full-access` なら動くが、セキュリティリスクあり

---

### 3. プロジェクト内に tmux ソケットを作成 ✅ 動作確認済み

**概要:**
```bash
# プロジェクト内にソケットを作成
tmux -S ./collab.sock new-session -s collab

# Codexをこのセッション内で起動
codex -s workspace-write

# Codexから別ペインにメッセージ送信
tmux -S ./collab.sock send-keys -t collab:1.2 'MESSAGE' Enter
```

**検証結果:**
- ✅ `workspace-write` sandbox で tmux コマンド実行可能
- ✅ Codex から別ペインへの `send-keys` 成功
- ✅ プロジェクト内ソケットなのでセキュリティリスクなし

**構成:**
```
./collab.sock (プロジェクト内tmuxソケット)
├── collab:1.1 (%0) - Codex
└── collab:1.2 (%1) - Claude Code (または他のペイン)
```

**課題:**
- 新しい tmux サーバーになる（既存セッションとは別）
- Claude Code と Codex の両方を同じソケットのセッションで動かす必要がある
- ワークフロー変更が必要（`tmux -S ./collab.sock attach` で接続）

**次のステップ:**
- Claude Code もこのソケットセッション内で起動する構成を実装
- 双方向通信のプロトコルを設計（メッセージフォーマット、完了通知など）

---

### 4. ファイルベース + inotifywait ❌ 外部依存

**概要:**
- Codex がレスポンスを `.codex-response.md` に書く
- 完了したら `.codex-done` ファイルを作成
- Claude が `inotifywait .codex-done` で待機（ポーリング不要）

**メリット:**
- tmux に依存しない
- イベントドリブン

**課題:**
- `inotifywait` は `inotify-tools` パッケージが必要（外部依存）
- インストールされていない環境では動かない

---

### 5. danger-full-access sandbox ⚠️ セキュリティリスク

**概要:**
- Codex を `codex -s danger-full-access` で起動
- プロジェクト外（`/tmp/tmux-*`）にもアクセス可能

**メリット:**
- 既存の tmux セッション構成を変更不要

**課題:**
- セキュリティ制限がほぼなくなる
- 信頼できる環境でのみ使用可能

---

## 現在の結論

**短期的（実装済み）:**
- ハイブリッド方式でプロンプト送信の破損問題は解決
- 完了検出はマーカー + アイドル検出のポーリングで対応

**中期的（検証完了）:**
- プロジェクト内 tmux ソケット方式で双方向通信が可能
- Codex から Claude Code ペインへの `send-keys` が動作確認済み

**✅ 実装完了（2026-01-19）:**
1. プロジェクト内ソケットセッションで Claude Code と Codex を起動する構成が動作確認済み
2. 双方向通信プロトコルを実装:
   - Claude → Codex: `send-keys` + ファイル参照（既存の `codex_send_prompt_file`）
   - Codex → Claude: `set-buffer` + `wait-for` によるイベントドリブン通知
3. ヘルパー関数を `scripts/codex-helpers.sh` に追加

---

### 6. バッファ + wait-for 方式 ✅ 実装済み

**概要:**
- tmux の `set-buffer` / `show-buffer` でデータを共有
- tmux の `wait-for` / `wait-for -S` でイベントドリブンな完了通知

**動作確認済み:**
```bash
# Codex側: レスポンスをバッファに書いてシグナル送信
tmux -S ./collab.sock set-buffer -b codex-response "レスポンスデータ"
tmux -S ./collab.sock wait-for -S codex-done

# Claude側: シグナルを待ってバッファを読む
tmux -S ./collab.sock wait-for codex-done
tmux -S ./collab.sock show-buffer -b codex-response
```

**メリット:**
- ✅ ポーリング不要のイベントドリブン
- ✅ `workspace-write` sandbox で動作
- ✅ プロジェクト内ソケットでセキュリティリスクなし
- ✅ `send-keys` の TUI 問題を回避（入力欄への送信不要）

**注意点:**
- Codex 側で tmux コマンド実行の承認が必要
  - 解決策1: `danger-full-access` sandbox を使う
  - 解決策2: Codex の設定で `tmux` コマンドを `don't ask` にする（推奨）

---

### 7. paste-buffer 方式 ✅ 実装済み（TUI間の直接通信）

**背景:**
`send-keys 'text' Enter` では TUI アプリ（Claude Code, Codex）の入力欄で
Enter が改行として扱われ、送信トリガーにならない問題があった。

**解決策:**
`paste-buffer` でテキストを貼り付け、その後 `send-keys Enter` を別途送信する。

```bash
# 1. テキストをファイルに書く
echo "message" > ./tmp/msg.txt

# 2. バッファにロード
tmux -S ./collab.sock load-buffer ./tmp/msg.txt

# 3. ターゲットペインにペースト
tmux -S ./collab.sock paste-buffer -t %4

# 4. Enter を別途送信（これが送信トリガーになる）
tmux -S ./collab.sock send-keys -t %4 Enter
```

**なぜ動くのか:**
- `paste-buffer` はテキストを「貼り付ける」だけで Enter は送らない
- その後の `send-keys Enter` は純粋な Enter キーとして送られる
- TUI アプリは純粋な Enter を送信トリガーとして認識する

**動作確認済み:**
- ✅ Claude → Codex: paste-buffer + send-keys Enter
- ✅ Codex → Claude: paste-buffer + send-keys Enter

**実装:**
- `codex_send_to_pane()` - 汎用の paste-buffer 送信関数
- `codex_send_to_claude()` - Codex → Claude 用ラッパー
- `codex_send_to_codex()` - Claude → Codex 用ラッパー

---

## 実装されたヘルパー関数

`scripts/codex-helpers.sh` に以下の関数を追加:

### 設定変数
```bash
CODEX_TMUX_SOCKET=""              # 空=デフォルトソケット、"./collab.sock"=プロジェクト内
CODEX_TMP_DIR="tmp"               # 一時ファイル用ディレクトリ（相対パスのみ）
CODEX_BUFFER_RESPONSE="codex-response"
CODEX_SIGNAL_CHANNEL="codex-done"
```

> **Note:** 双方向通信（バッファ + wait-for）を使用する場合は、`CODEX_TMUX_SOCKET="./collab.sock"` を設定してください。

> **Note:** `CODEX_TMP_DIR` は相対パスのみをサポートします。絶対パスを指定するとパス結合が壊れます。

### バッファ通信
- `codex_set_buffer "name" "data"` - バッファにデータ書き込み
- `codex_get_buffer "name"` - バッファからデータ読み取り
- `codex_buffer_exists "name"` - バッファ存在確認
- `codex_clear_buffer "name"` - バッファ削除

### シグナル通信
- `codex_send_signal "channel"` - シグナル送信（Codex側）
- `codex_wait_signal "channel"` - シグナル待機（ブロッキング）
- `codex_wait_signal_timeout "channel" 30` - タイムアウト付き待機

### 統合パターン
- `codex_wait_response "channel" "buffer" 60` - シグナル待機 + バッファ読み取り
- `codex_respond "data" "channel" "buffer"` - データ書き込み + シグナル送信（Codex側）

### paste-buffer 送信（TUI間通信）
- `codex_send_to_pane "pane_id" "message"` - 汎用 paste-buffer 送信
- `codex_send_to_claude "pane_id" "message"` - Codex → Claude 用
- `codex_send_to_codex "pane_id" "message"` - Claude → Codex 用

### Codex 自動承認（セキュア）
- `codex_get_pending_command "pane_id"` - 承認待ちコマンドを取得
  - `capture-pane -J -S -30` で末尾30行を折り返し結合して取得
  - 末尾10行に「Press enter to confirm」または「› 1. Yes, proceed」があるかでアクティブダイアログを判定
  - `$`行は `tail -1` で最新のダイアログを優先（複数ダイアログ対応）
- `codex_approve_if_matches "pane_id" "pattern"` - パターンに一致すれば承認
  - 引数チェック（pane_id, pattern必須）
  - 空patternは拒否（誤承認防止）
  - `send-keys y` + `send-keys Enter` で確実に承認
- `codex_approve_response_commands "pane_id" [timeout]` - set-buffer + wait-for を自動承認
  - timeout数値検証（デフォルト30秒）

### Collab セッション管理
- `codex_collab_session_start [options]` - collabセッションを作成またはアタッチ
  - `--socket PATH` - ソケットパス（デフォルト: ./collab.sock）
  - `--session NAME` - セッション名（デフォルト: collab）
  - `--attach` - 作成後にアタッチ
  - `--start-codex` - 右ペインでCodexを起動（新規セッション時のみ有効）
  - `--start-claude` - 左ペインでClaude Codeを起動（新規セッション時のみ有効）
  - ペインIDを `tmp/codex-pane-id` / `tmp/claude-pane-id` に保存（既存セッション時も更新）
  - `pane_index` を使用して左右のペインを確実に判別
- `codex_collab_session_exists [options]` - セッションの存在確認
- `codex_collab_session_info [options]` - セッション情報の表示
- `codex_collab_session_kill [options]` - セッションの終了

**注意点:**
- 既存セッション時は `--start-codex` / `--start-claude` フラグは無視される
- 既存セッション時もペインIDファイルは更新される

**使用例:**
```bash
# セッション作成（Codex自動起動）
source scripts/codex-helpers.sh
codex_collab_session_start --start-codex --attach

# 既存セッションにアタッチ
tmux -S ./collab.sock attach-session -t collab
```

---

## 関連ファイル

- `scripts/codex-helpers.sh` - ヘルパー関数
  - `codex_send_prompt()` - 従来のプロンプト送信
  - `codex_send_prompt_file()` - ハイブリッド方式のプロンプト送信
  - `codex_wait_completion()` - 完了検出（ポーリング）
  - `codex_set_buffer()` / `codex_get_buffer()` - バッファ通信
  - `codex_send_signal()` / `codex_wait_signal()` - シグナル通信
  - `codex_wait_response()` / `codex_respond()` - 統合パターン
  - `codex_send_to_pane()` / `codex_send_to_claude()` / `codex_send_to_codex()` - paste-buffer TUI間通信
  - `codex_get_pending_command()` / `codex_approve_if_matches()` / `codex_approve_response_commands()` - 自動承認
  - `codex_collab_session_start()` / `codex_collab_session_exists()` / `codex_collab_session_info()` / `codex_collab_session_kill()` - セッション管理
- `commands/collab.md` - /collab コマンド
- `commands/collab-attach.md` - /collab-attach コマンド

## 環境情報

- tmux ソケット:
  - デフォルト: `/tmp/tmux-1001/default`（プロジェクト外、sandbox制限あり）
  - プロジェクト内: `./collab.sock`（推奨、`workspace-write` sandboxで動作）
- 設定変数 `CODEX_TMUX_SOCKET`:
  - 空（デフォルト）: システムデフォルトソケットを使用
  - `./collab.sock`: プロジェクト内ソケットを使用（双方向通信に必要）
- Codex sandbox: `workspace-write` ではプロジェクト外アクセス不可
- inotify-tools: 未インストール
