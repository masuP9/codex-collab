# codex-collab

Claude Code と OpenAI Codex CLI を協調させてタスクを実行するプラグイン。

## 概要

このプラグインは、Claude Code と Codex の強みを組み合わせた協調ワークフローを提供します。

**基本パターン（レビュー型）:**
- **Codex**: 計画作成・コードレビュー
- **Claude Code**: 実装

## インストール

```bash
# プラグインディレクトリにコピー済み
# ~/.claude/plugins/codex-collab/
```

## 前提条件

- OpenAI Codex CLI (`codex`) がインストールされていること
- 環境変数 `OPENAI_API_KEY` が設定されていること
- WSL環境: Windows Terminal (`wt.exe`) が利用可能であること

## 使い方

### `/collab` コマンド

協調ワークフローを開始します。

```
/collab 新しい認証機能を実装して
```

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

## ライセンス

MIT
