# tmux でリアルタイム出力を確認する方法

Codex の出力をリアルタイムで確認したい場合の設定方法。

## 前提条件

- tmux 環境で作業していること
- `script` コマンドが利用可能（ほとんどの Unix 系 OS で標準）

## ワークフロー

### Step 1: 出力ファイルを準備

```bash
CODEX_OUTPUT="./tmp/codex-collab-$(date +%s).txt"
touch "$CODEX_OUTPUT"
```

### Step 2: 監視用ペインを起動

```bash
# 右側に新しいペインを開いて tail -f を実行
tmux split-window -h "tail -f $CODEX_OUTPUT; read"
```

オプション:
- `-h`: 水平分割（右側に開く）
- `-v`: 垂直分割（下側に開く）
- `-p 40`: ペインサイズを40%に指定

### Step 3: Codex を実行（リアルタイム出力）

```bash
# script コマンドでPTYを確保（バッファリング回避）
script -q "$CODEX_OUTPUT" -c 'codex exec -s read-only "プロンプト"'
```

または `stdbuf` を使う場合:
```bash
stdbuf -oL codex exec -s read-only "プロンプト" > "$CODEX_OUTPUT" 2>&1
```

### Step 4: 完了後、監視ペインを閉じる

```bash
# 最後に開いたペインを閉じる
tmux kill-pane -t {last}
```

## 一連のコマンド例

```bash
# 変数設定
CODEX_OUTPUT="./tmp/codex-collab-$(date +%s).txt"
touch "$CODEX_OUTPUT"

# 監視ペインを起動
tmux split-window -h "tail -f $CODEX_OUTPUT; read"

# Codex 実行
script -q "$CODEX_OUTPUT" -c 'codex exec -s read-only "
あなたの役割は実装計画を作成することです。

## タスク
ユーザー認証機能を追加する

## 出力形式
1. 変更するファイル一覧
2. 実装手順
3. リスク評価
"'

# 結果を読み取り（Claude Code が処理）
cat "$CODEX_OUTPUT"

# 監視ペインを閉じる
tmux kill-pane -t {last}
```

## 注意点

### script コマンドの出力

`script` は制御文字（ANSIエスケープシーケンス等）も記録するため、出力に色コードなどが含まれる場合があります。クリーンなテキストが必要な場合:

```bash
# 制御文字を除去
cat "$CODEX_OUTPUT" | sed 's/\x1b\[[0-9;]*m//g'
```

### tmux セッション外での実行

tmux セッション外から実行する場合は、セッションを指定:

```bash
tmux split-window -t mysession:0 -h "tail -f $CODEX_OUTPUT"
```

## 設定の自動化

`.claude/codex-collab.local.md` に以下を追加することで、tmux モードを有効化できます:

```yaml
---
model: o4-mini
sandbox: read-only
realtime-output: true  # tmux でリアルタイム出力を有効化
---
```

この設定がある場合、Claude Code は自動的に tmux ペインを使用します。
