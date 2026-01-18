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

## 使い方

### `/collab` コマンド

協調ワークフローを開始します。

```
/collab 新しい認証機能を実装して
```

**自動検出機能 (tmuxモード):**
- tmuxセッション内で実行時、`.codex-pane-id`がなくても既存のCodexペインを自動検出
- 検出されたペインは`.codex-pane-id`に保存され、attached modeで使用
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
- ペインIDは`.codex-pane-id`に保存され、次回自動検出
- **セッション状態管理**: 初回は完全コンテキスト、継続時は軽量な`## Update`形式で送信（トークン節約）
- セッションは30分でタイムアウト（`.codex-session-state`で管理）

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

## 構造化通信プロトコル

Claude Code と Codex CLI 間の通信を構造化するための YAML ベースのプロトコルを実装しています。

### プロトコルの目的

- **一貫性**: 両者間のメッセージ形式を統一
- **パース可能**: YAML形式で機械的に処理可能
- **ゼロ設定**: プロジェクトごとの設定不要（プラグインが自動でヘッダーを付与）

### プロトコルヘッダー

すべての Codex へのプロンプトに以下のヘッダーが自動的に付与されます：

```yaml
## Protocol (codex-collab/v1)
format: yaml
rules:
  - respond with exactly one top-level YAML mapping
  - include required fields: type, id, status, body
  - if unsure or blocked, use type=action_request with clarifying questions
  - include next_action (continue|stop) to signal exchange flow
types:
  task_card: {body: title, context, requirements, acceptance_criteria, proposed_steps, risks, test_considerations}
  result_report: {body: summary, changes, tests, risks, checks}
  action_request: {body: question, options, expected_response}
  review: {body: verdict, summary, findings, suggestions}
status: [ok, partial, blocked]
verdict: [pass, conditional, fail]
severity: [low, medium, high]
next_action: [continue, stop]
```

### メッセージタイプ

| タイプ | 用途 | 使用者 |
|--------|------|--------|
| `task_card` | タスク定義と受け入れ基準 | Codex（計画時） |
| `result_report` | 実行結果とチェック状態 | Claude（報告時） |
| `action_request` | 情報や決定の要求 | 両方 |
| `review` | レビュー結果と指摘事項 | Codex（レビュー時） |

### メッセージ例

**Codexからの計画（task_card）:**

```yaml
type: task_card
id: plan-001
status: ok
body:
  title: "認証機能の実装"
  context: "既存のExpress APIに認証を追加"
  requirements:
    - "JWT ベースの認証"
    - "ログイン/ログアウト エンドポイント"
  acceptance_criteria:
    - "認証なしでは保護されたルートにアクセスできない"
    - "有効なトークンで認証が成功する"
  proposed_steps:
    - step: 1
      action: create
      file: src/middleware/auth.ts
      description: "JWT検証ミドルウェアを作成"
    - step: 2
      action: modify
      file: src/routes/index.ts
      description: "認証ルートを追加"
  risks:
    - "既存のルートに影響する可能性"
  test_considerations:
    - "認証成功/失敗のテストケース"
```

**Codexからのレビュー（review）:**

```yaml
type: review
id: review-001
status: ok
body:
  verdict: conditional
  summary: "実装は概ね良好だが、エラーハンドリングに改善の余地あり"
  findings:
    - severity: medium
      location: src/middleware/auth.ts:25
      message: "トークン期限切れ時のエラーメッセージが不明確"
      suggestion: "具体的なエラーコードを返す"
    - severity: low
      location: src/routes/auth.ts:10
      message: "ログ出力が不足"
      suggestion: "認証イベントをログに記録"
  suggestions:
    - "レート制限の追加を検討"
    - "リフレッシュトークンの実装"
```

### パース戦略

- **寛容**: 必須フィールドのみを検証
- **許容**: 追加フィールドを受け入れる
- **フォールバック**: YAMLパースに失敗した場合は非構造化パースに切り替え

### マルチターン交換

#### Planning Exchange（計画段階）

Codex が `next_action: continue` または `type: action_request` で応答した場合、Claude Code は交換ループに入ります：

1. Claude が Codex の質問/リクエストに応答
2. Codex が追加の回答または最終結果を返す
3. `next_action: stop` または `exchange.max_iterations` に達するまで継続

**設定 (`exchange.*`):**
| 設定 | デフォルト | 説明 |
|------|-----------|------|
| `exchange.enabled` | `true` | グローバルキルスイッチ |
| `exchange.max_iterations` | `3` | 最大イテレーション数 |
| `exchange.user_confirm` | `on_important` | ユーザー確認タイミング |
| `exchange.history_mode` | `summarize` | 履歴管理方式 |

#### Review Iteration（レビュー段階）

レビューで CONDITIONAL または FAIL が返された場合、自動的に修正→再レビューのイテレーションが行われます：

1. Claude が指摘事項を修正
2. Codex が再レビュー
3. PASS または `review.max_iterations` に達するまで継続

**設定 (`review.*`):**
| 設定 | デフォルト | 説明 |
|------|-----------|------|
| `review.enabled` | `true` | レビューイテレーションの有効化 |
| `review.max_iterations` | `5` | 最大イテレーション数（ゴールが明確なので多め） |
| `review.user_confirm` | `never` | 自動でイテレーション |

**注**: `exchange.*` と `review.*` は完全に独立した設定です（継承なし）。

### 関連ファイル

詳細なスキーマとテンプレートは `skills/codex-collaboration/references/` にあります：

- `protocol-cheatsheet.yaml` - プロンプト用の最小限ヘッダー
- `protocol-schema.yaml` - 完全なスキーマ定義と例
- `planning-prompt.md` - 計画依頼テンプレート
- `review-prompt.md` - レビュー依頼テンプレート

## ライセンス

MIT
