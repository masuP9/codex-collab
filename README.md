# codex-collab

Claude Code と OpenAI Codex CLI を協調させてタスクを実行するプラグイン。

## 概要

このプラグインは、Claude Code と Codex の強みを組み合わせた協調ワークフローを提供します。`codex exec` によるステートレス実行で Codex と通信し、シンプルなアーキテクチャを実現しています。

**Codex-Leads（従来のレビュー型）:**
- **Codex**: 計画作成・コードレビュー
- **Claude Code**: 実装

**Claude-Leads（新規）:**
- **Claude Code**: 深い分析・計画作成・レビュー
- **Codex**: 高速実装（workspace-write sandbox）

## インストール

```bash
# マーケットプレイスを追加
/plugin marketplace add https://github.com/masuP9/codex-collab

# プラグインをインストール
/plugin install codex-collab@codex-collab
```

## 前提条件

- OpenAI Codex CLI (`codex`) がインストールされていること
- `codex exec` が動作すること（`echo "test" | codex exec -s read-only -`）
- 環境変数 `OPENAI_API_KEY` が設定されていること

## アーキテクチャ

Codex CLI との通信は `codex exec`（ステートレス実行）を使用します:

```
Claude Code → Bash tool → codex exec → stdout 取得 → パース
```

- プロンプトを stdin から渡し、結果を stdout で受け取るシンプルな構造
- 各呼び出しは独立（会話コンテキストはプロンプト内に明示的に含める）
- `codex_run_exec()` が入出力、ANSI エスケープ除去、exit code ハンドリングを統合処理
- バックグラウンド実行が必要な場合は Bash tool の `run_in_background: true` を使用

## プロジェクト構造

```
codex-collab/
├── .claude-plugin/
│   └── plugin.json         # プラグインメタデータ
├── commands/
│   ├── collab-codex.md     # /collab-codex コマンド
│   ├── strong-inference.md # /strong-inference コマンド
│   └── devils-advocate.md  # /devils-advocate コマンド
├── scripts/
│   └── codex-helpers.sh    # 共通ヘルパー関数
└── skills/
    ├── codex-collaboration/
    │   └── references/     # プロトコル定義
    ├── strong-inference/
    │   └── references/     # 仮説テンプレート
    └── devils-advocate/
        └── references/     # 評価基準
```

### ヘルパースクリプト

`scripts/codex-helpers.sh` には、コマンド間で共有される関数が定義されています:

**コア関数（Codex 実行）:**
- `codex_run_exec()` - codex exec のラッパー（stdin パイプ、ANSI 除去、出力保存、exit code ハンドリング）
- `codex_build_exec_command()` - codex exec コマンド文字列の構築
- `codex_write_prompt()` - プロンプトを一時ファイルに書き出し
- `codex_strip_ansi()` - ANSI エスケープコード除去

**ユーティリティ関数:**
- `codex_ensure_tmp_dir()` - 一時ディレクトリ管理
- `codex_tmp_path()` - 一時ディレクトリ内のファイルパス取得
- `codex_hash_content()` - クロスプラットフォームハッシュ計算
- `codex_generate_signal()` - ユニークID生成
- `codex_get_language_directive()` - 言語指示生成
- `codex_debug()` - デバッグログ出力

**メタデータ抽出:**
- `codex_extract_metadata()` - 応答末尾のYAMLブロックを抽出
- `codex_get_field()` - メタデータフィールド取得
- `codex_get_status()` - status フィールド取得（continue/stop）
- `codex_get_verdict()` - verdict フィールド取得（pass/conditional/fail）

各コマンドは自動的にヘルパーをsourceします。

## 使い方

### `/collab-codex` コマンド

協調ワークフローを開始します。

```
/collab-codex 新しい認証機能を実装して
```

**Codex 呼び出し:**
- `codex exec` によるステートレス実行（ブロッキング、stdout 出力）
- 各呼び出しは独立（会話コンテキストはプロンプト内に明示的に含める）
- Codex CLI が未インストールの場合は Claude-only モードにフォールバック

### `/strong-inference` コマンド

Strong Inference（強い推論）メソッドを使って、仮説駆動でバグ調査を行います。

```
# 基本的な使い方
/strong-inference APIが時々500エラーを返す

# モード指定
/strong-inference --mode claude-only テストがフレーキーな原因を調べて
```

**特徴:**
- 2-4個の競合仮説を生成
- 各仮説を排除する「キラー実験」を設計
- 仮説ツリーを `tmp/strong-inference/` に保存（調査状態を永続化）
- codexモードではCodexが仮説生成、Claudeが検証実行

### `/devils-advocate` コマンド

Devil's Advocate（悪魔の代弁者）メソッドを使って、設計案や仮説をストレステストします。

```
# 基本的な使い方
/devils-advocate このキャッシュ設計を検証して

# モード指定
/devils-advocate --mode claude-only マイクロサービス移行は妥当か

# ラウンド数指定
/devils-advocate --max-rounds 5 この認証設計
```

**特徴:**
- Blue Team（提案側）vs Red Team（批判側）の構造化議論
- 3ラウンド（デフォルト）の反論・再反論
- 最終評価: APPROVE / CONDITIONAL / REJECT
- codexモードではCodexがRed Team、ClaudeがBlue Team
- 議論ログを `tmp/devils-advocate/` に保存

### スキルの自動起動

以下のようなリクエストで自動的にスキルが有効になります:
- 「Codexと協調してタスクを実行したい」
- 「Codexにレビューを依頼して」
- 「Codexに計画を作成させたい」
- 「このバグの原因を調査して」（Strong Inferenceスキル）
- 「仮説を立てて検証して」（Strong Inferenceスキル）
- 「この設計を批判的にレビューして」（Devil's Advocateスキル）
- 「反論をもらいたい」（Devil's Advocateスキル）

### Strong Inference vs Devil's Advocate の使い分け

両スキルは目的が異なります。以下のガイドを参考にしてください。

#### ユースケース別の推奨スキル

| ユースケース | 推奨スキル | 理由 |
|-------------|-----------|------|
| バグの原因調査 | `/strong-inference` | 競合仮説を立て、実験で排除 |
| パフォーマンス問題の調査 | `/strong-inference` | 原因を絞り込む検証が必要 |
| なぜ動かないか分からない | `/strong-inference` | 未知の原因を特定する |
| 設計案のレビュー | `/devils-advocate` | 反論を通じて弱点を発見 |
| アーキテクチャ決定の検証 | `/devils-advocate` | 議論で合意形成 |
| リスク評価 | `/devils-advocate` | 批判的視点で穴を見つける |
| PRのコードレビュー | `/collab-codex` | 実装済みコードの品質確認 |

#### 判断が難しいケース

**「仮説を検証したい」と言われたら？**
- 原因不明の問題 → `/strong-inference`（実験で仮説を排除）
- 設計案の妥当性 → `/devils-advocate`（議論で仮説を強化）

**「レビューしてほしい」と言われたら？**
- 実装済みコード → `/collab-codex`（品質チェック）
- 設計案・提案 → `/devils-advocate`（批判的検証）

#### 簡単な見分け方

```
「なぜ？」「原因は？」 → /strong-inference
「これで良いか？」「弱点は？」 → /devils-advocate
「実装をチェック」 → /collab-codex
```

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
| `workflow` | `auto` | ワークフロー選択 (auto, codex-leads, claude-leads) |
| `model` | (Codexデフォルト) | 使用するモデル (o3, o4-mini等) |
| `sandbox` | `read-only` | サンドボックスモード (read-only, workspace-write, danger-full-access)。codex-leads用 |
| `exchange.enabled` | `true` | Planning exchangeのグローバルキルスイッチ (codex-leads) |
| `exchange.max_iterations` | `3` | Planning exchangeの最大ラウンド数 |
| `exchange.user_confirm` | `on_important` | ユーザー確認タイミング (never, always, on_important) |
| `exchange.history_mode` | `summarize` | 履歴管理方式: full=全履歴保持, summarize=最新2ラウンドのみ全文 |
| `review.enabled` | `true` | Review iterationの有効化 (codex-leads) |
| `review.max_iterations` | `5` | Review iterationの最大ラウンド数（ゴールが明確なので多め） |
| `review.user_confirm` | `never` | レビュー時は自動でイテレーション |
| `claude_leads.sandbox` | `workspace-write` | Codex実装用サンドボックス (claude-leads) |
| `claude_leads.consult_codex` | `true` | 計画の壁打ちフェーズ有効化 (claude-leads) |
| `claude_leads.safety_checkpoint` | `stash` | 実装前チェックポイント (stash, wip-commit, none) |
| `claude_leads.review.max_iterations` | `3` | Claudeレビュー修正ループの上限 (claude-leads) |

### 設定の優先順位

```
コマンド引数 > プロジェクト設定 > グローバル設定 > 安全デフォルト
```

## ワークフロー

### Codex-Leads（従来）

Codex が計画・レビュー、Claude が実装するワークフロー。推論に優れたモデル（o3, gpt-5等）に最適。

```
1. ユーザー: /collab-codex "機能Xを実装して"
2. Claude Code: タスク分析・Codex向けプロンプト作成
3. Codex: 計画作成
4. Claude Code: 計画確認・実装
5. Codex: レビュー（Pass/Fail/Conditional）
6. Claude Code: 修正（必要に応じて）・完了報告
```

### Claude-Leads（新規）

Claude が計画・レビュー、Codex が実装するワークフロー。高速実行向きモデル（codex-mini, o4-mini等）に最適。

```
1. ユーザー: /collab-codex "機能Xを実装して"
2. Claude Code: 深いコードベース分析
3. Claude Code: 詳細な実装計画を作成
4. (optional) Codex: 計画をレビュー（壁打ち）
5. ユーザー: 計画を承認
6. Safety Checkpoint: git stash で状態保存
7. Codex: 計画に従い実装（workspace-write sandbox）
8. Claude Code: 変更をレビュー（git diff + Read）
9. [問題あり?] → Codex修正 → Claude再レビュー
10. 完了報告
```

### ワークフロー自動選択

`workflow: auto`（デフォルト）では、常に **codex-leads** を選択します。`claude-leads` は `workflow: claude-leads` を明示的に指定した場合のみ有効です。

### Claude-Leads の責務境界

| 役割 | 責務 |
|------|------|
| **Claude** | 品質ゲート: 分析・計画・レビュー・承認 |
| **Codex** | 実行エンジン: 計画に従った正確な実装 |
| **ユーザー** | 最終承認: 計画承認と最終判断 |

> **安全メカニズム**: Safety Checkpoint（git stash）+ 計画外ファイル変更の自動検出 + Claude レビュー

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
