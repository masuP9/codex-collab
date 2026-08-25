# codex-collab

Claude Code と OpenAI Codex CLI を協調させてタスクを実行するプラグイン。

Claude Code から Codex を呼び出す既存フローに加え、Codex から Claude Code を read-only の相談役として呼び出す `claude-collab` スキルも提供します。

## 概要

このプラグインは、Claude Code と Codex の強みを組み合わせた協調ワークフローを提供します。**MCP primary + Bash fallback** のデュアルモードアーキテクチャで Codex と通信します。

**Codex-Leads（従来のレビュー型）:**
- **Codex**: 計画作成・コードレビュー
- **Claude Code**: 実装

**Claude-Leads（新規）:**
- **Claude Code**: 深い分析・計画作成・レビュー
- **Codex**: 高速実装（workspace-write sandbox）

## インストール

### Claude Code から使う

```bash
# マーケットプレイスを追加
/plugin marketplace add https://github.com/masuP9/codex-collab

# プラグインをインストール
/plugin install codex-collab@codex-collab
```

### Codex から使う

Codex のスキルディレクトリへシンボリックリンクを作成します。

```bash
mkdir -p "${CODEX_HOME:-$HOME/.codex}/skills"
ln -s "$(pwd)/skills/claude-collab" "${CODEX_HOME:-$HOME/.codex}/skills/claude-collab"
```

Codex で「Claude と一緒に実装して」「Claude にレビューしてもらって」のように依頼すると、`claude-collab` スキルが Claude Code CLI を read-only の相談役として呼び出します。

## 前提条件

- OpenAI Codex CLI (`codex`) がインストールされていること
- `codex exec` が動作すること（`echo "test" | codex exec -s read-only -`）
- 環境変数 `OPENAI_API_KEY` が設定されていること
- (推奨) Codex MCP サーバー設定済み（`codex mcp-server`）
- Codex から `claude-collab` を使う場合は Claude Code CLI (`claude`) がインストール済みであること

## アーキテクチャ

Codex CLI との通信は **MCP primary + Bash fallback** のデュアルモードを採用しています。

### MCP モード（推奨）

Codex MCP サーバー (`codex mcp-server`) 経由でステートフルなセッション管理:

```
Claude Code → mcp__codex__codex → threadId で会話継続 → mcp__codex__codex-reply
```

- ステートフル: `threadId` で会話コンテキスト保持（multi-turn exchange で履歴再構築不要）
- クリーンテキスト: ANSI 除去不要
- ファイル I/O 不要: prompt/output の tmp ファイル不要

### Bash モード（フォールバック）

MCP が利用できない場合は `codex exec`（ステートレス実行）にフォールバック:

```
Claude Code → Bash tool → codex exec → stdout 取得 → パース
```

- プロンプトを stdin から渡し、結果を stdout で受け取るシンプルな構造
- 各呼び出しは独立（会話コンテキストはプロンプト内に明示的に含める）
- `codex_run_exec()` が入出力、ANSI エスケープ除去、exit code ハンドリングを統合処理

### モード自動判定

スキル起動時に MCP の可用性を自動プローブし、利用可能なら MCP モード、不可なら Bash モードにフォールバックします。

## プロジェクト構造

```
codex-collab/
├── .claude-plugin/
│   ├── plugin.json            # プラグインメタデータ
│   └── marketplace.json       # マーケットプレイス公開用メタデータ
├── commands/
│   ├── codex-collab.md        # /codex-collab コマンド
│   ├── collab-planning.md     # /collab-planning コマンド
│   ├── strong-inference.md    # /strong-inference コマンド
│   ├── devils-advocate.md     # /devils-advocate コマンド
│   ├── dialectic-loop.md      # /dialectic-loop コマンド
│   └── contradiction-lift.md  # /contradiction-lift コマンド
├── hooks/
│   ├── enforce-skill-usage.sh # PreToolUse フック（スキル経由強制）
│   └── enforce-skill-usage.md # フック設定ドキュメント
├── scripts/
│   ├── codex-helpers.sh       # 共通ヘルパー関数
│   └── test-helpers.sh        # ヘルパーのテストスイート
├── docs/
│   └── bash-usage.md          # Bash 使用ルール詳細
└── skills/
    ├── codex-collab/
    │   └── references/        # プロトコル定義・テンプレート
    ├── claude-collab/
    │   ├── scripts/           # Codex から Claude を呼ぶ read-only ヘルパーとテスト
    │   └── references/        # Claude 相談・レビュー用テンプレート
    ├── collab-planning/
    │   └── references/        # 計画テンプレート・レビュー基準
    ├── strong-inference/
    │   └── references/        # 仮説テンプレート
    ├── devils-advocate/
    │   └── references/        # 評価基準・批評テンプレート
    ├── dialectic-loop/
    │   └── references/        # 予測・帰納検証・アブダクションテンプレート
    └── contradiction-lift/
        └── references/        # 封緘解・矛盾マップ・止揚監査テンプレート
```

### ヘルパースクリプト

`scripts/codex-helpers.sh` には、コマンド間で共有される関数が定義されています:

**コア関数（Bash fallback 用の Codex 実行）:**
- `codex_run_exec()` - codex exec のラッパー（stdin パイプ、ANSI 除去、出力保存、exit code ハンドリング）
- `codex_build_exec_command()` - codex exec コマンド文字列の構築
- `codex_write_prompt()` - プロンプトを一時ファイルに書き出し
- `codex_strip_ansi()` - ANSI エスケープコード除去

**レビュー解析（Bash fallback 用）:**
- `codex_run_review()` - codex review --uncommitted のラッパー（sandbox_mode 指定、ANSI 除去、出力保存、モデル retry、exit code ハンドリング）
- `codex_infer_verdict()` - レビューレスポンスから verdict を推定（メタデータ → [P1]-[P4] → findings なし pass）
- `codex_extract_review_findings()` - レビューレスポンスから findings を抽出

**セッション状態管理（MCP/Bash デュアルモード用）:**
- `codex_save_session_state()` - セッション状態を JSON ファイルに保存（task_id 単位で分離）
- `codex_load_session_state()` - セッション状態を読み込み（MODE, THREAD_ID 等をグローバル変数にセット）
- `codex_save_thread()` - 名前付きスレッドを保存（claude-leads の Thread B/C 用）
- `codex_load_thread()` - 名前付きスレッドを読み込み
- `codex_sanitize_task_id()` - task_id のファイル名安全化（英数字・ハイフン・アンダースコアのみ）
- `codex_json_escape()` - JSON 値のエスケープ（引用符・バックスラッシュ・改行）
- `codex_diff_tier()` - diff のサイズに応じてティア判定（small/medium/large）

**メタデータ抽出:**
- `codex_extract_metadata()` - 応答末尾のYAMLブロックを抽出
- `codex_get_field()` - メタデータフィールド取得
- `codex_get_status()` - status フィールド取得（continue/stop）
- `codex_get_verdict()` - verdict フィールド取得（pass/conditional/fail）

**ユーティリティ関数:**
- `codex_ensure_tmp_dir()` - 一時ディレクトリ管理
- `codex_tmp_path()` - 一時ディレクトリ内のファイルパス取得
- `codex_hash_content()` - クロスプラットフォームハッシュ計算
- `codex_generate_signal()` - ユニークID生成
- `codex_get_language_directive()` - 言語指示生成（多言語対応）
- `codex_debug()` - デバッグログ出力

各コマンドは自動的にヘルパーをsourceします。

## 使い方

### `/codex-collab` コマンド

協調ワークフローを開始します。計画・実装・レビューの完全サイクル。

```
/codex-collab 新しい認証機能を実装して
```

**特徴:**
- MCP モードではステートフルなセッションで Codex と対話
- Bash フォールバック: `codex exec` によるステートレス実行
- Codex CLI が未インストールの場合は Claude-only モードにフォールバック

### `/collab-planning` コマンド

Codex と協調して実装計画を作成します。**計画のみ — 実装は行いません。**

```
# 基本的な使い方
/collab-planning ユーザーリストAPIにページネーションを追加したい

# イテレーション数指定
/collab-planning --max-iterations 5 認証モジュールのリファクタリング計画

# モード指定
/collab-planning --mode claude-only データベース移行の計画を立てたい
```

**特徴:**
- Claude がコンテキスト収集・ドラフト作成、Codex がレビュー・改善提案
- 固定テンプレート出力（目的/スコープ外/WBS/実装手順/リスク/検証/完了条件）
- 品質評価に基づく自動イテレーション（good → 完了、needs-improvement → 改善、major-revision → ユーザー確認）
- 各ラウンド末に要約スナップショット（決定事項/未解決/却下案）で文脈劣化を防止
- 計画ログを `tmp/collab-planning/` に保存

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

### `/dialectic-loop` コマンド

経験的な主張を Peirce の探究サイクル（演繹→帰納→仲裁）で現物データに照らして検証・精緻化します。

```
# 主張を corpus で検証
/dialectic-loop "このコードベースは合成を継承より好む" --corpus "src/**/*.ts"

# Codex に仮説生成から任せる（アブダクション variant）
/dialectic-loop --abduce --corpus "scripts/**/*.sh"
```

**特徴:**
- 演繹役（Claude）が反証可能な予測、帰納役（Codex, 独立）が現物コーパスをスクリプト集計＋反例探索、仲裁役（Claude）がスコアカードで H′ に更新
- `--abduce` で仮説生成自体を Codex に委譲（著者≠仲裁の独立性）
- 出力は「更新された仮説 H′ ＋ confidence ＋ 元の枠組みが見落とした点」
- ループログを `tmp/dialectic-loop/` に保存

### `/contradiction-lift` コマンド

Claude と Codex に**同じ問いを独立に解かせ**、答えの食い違いを止揚（アウフヘーベン）します。平均でも折衷でもなく、両者の真理契機を保存したまま一段高い枠へ。

```
# 実行で決着しない設計/価値の二択を止揚
/contradiction-lift "ループは段数固定か収束検知か"
```

**特徴:**
- 状態機械: contract → sealed → mapped → adjudicated → preserved → lifted → accepted | aporia | no_material_divergence
- 立場を事前割当せず、独立解の食い違いから矛盾を立ち上げる（devils-advocate の外部反対役とは逆）
- 出力は**選択機構 `f(C)→A|B|N`** か **正直なアポリア**（偽の総合に逃げない）
- 経験的に決着する対立は Codex 実行へ routing。ログを `tmp/contradiction-lift/` に保存

### スキルの自動起動

以下のようなリクエストで自動的にスキルが有効になります:
- 「Codexと協調してタスクを実行したい」（codex-collabスキル）
- 「Codexにレビューを依頼して」（codex-collabスキル）
- 「Codexに計画を作成させたい」（codex-collabスキル）
- 「計画を立てたい」「実装計画を作成して」（collab-planningスキル）
- 「Codexと計画を練りたい」「plan with Codex」（collab-planningスキル）
- 「このバグの原因を調査して」（Strong Inferenceスキル）
- 「仮説を立てて検証して」（Strong Inferenceスキル）
- 「この設計を批判的にレビューして」（Devil's Advocateスキル）
- 「反論をもらいたい」（Devil's Advocateスキル）
- 「この傾向分析の仮説をデータで検証して精緻化して」（Dialectic Loopスキル）
- 「主張を現物で裏取りしたい」「演繹と帰納で検証」（Dialectic Loopスキル）
- 「2つの案が食い違う、平均でなく止揚したい」（Contradiction Liftスキル）
- 「独立案を統合」「矛盾を止揚」「アウフヘーベン」（Contradiction Liftスキル）

### スキルの使い分け

スキルは目的が異なります。**多くの場合、スキル名を覚える必要はありません**——やりたいことを自然文で書けば、内容から適切なスキルが自動的に起動します（上記「スキルの自動起動」）。能動的に選びたいとき・迷うときは、以下のガイドを参照してください。

スキルは大きく **実行系**（実装/計画）と **分析系**（思考フレームワーク）に分かれます。

#### 実行系

| スキル | 目的 |
|--------|------|
| `/codex-collab` | 計画〜実装〜レビューの完全サイクル（中小タスク、PR レビュー） |
| `/collab-planning` | 計画のみ（成果物は計画文書、実装は起動しない） |
| `claude-collab` | Codex 側から Claude を read-only の相談役として呼ぶ（Codex で使用） |

#### 分析系（思考フレームワーク）— ここが一番迷いやすい

| スキル | いつ使うか | 矛盾の出所 | 出力 |
|--------|-----------|-----------|------|
| `/strong-inference` | **未知の原因**を究明（バグ/デバッグ） | 競合仮説 | 根本原因＋証拠 |
| `/devils-advocate` | **1つの提案**を反証でストレステスト | 外から割り当てた反対役 | APPROVE/CONDITIONAL/REJECT |
| `/dialectic-loop` | **経験的主張**を現物データで検証・精緻化 | 予測 vs 現物の証拠 | 更新された仮説 H′＋confidence |
| `/contradiction-lift` | **独立した2つの解**の食い違いを止揚 | 独立解から自然に立ち上がる | 選択機構 or 正直なアポリア |

#### 判断が難しいケース

**「計画を立てたい」と言われたら？**
- 計画のみが目的 → `/collab-planning`
- 計画 + 実装まで → `/codex-collab`

**「検証/レビューしたい」と言われたら？**
- 実装済みコード → `/codex-collab`（品質チェック）
- 原因不明の問題（なぜ動かない） → `/strong-inference`（実験で仮説を排除）
- 1つの設計案の妥当性 → `/devils-advocate`（反論で弱点を発見）
- 主張やトレンドが現物データと合うか → `/dialectic-loop`（演繹→帰納→仲裁で精緻化）
- 実装計画 → `/collab-planning`（Codex にレビューしてもらう）

**「2つの案で迷っている」と言われたら？**
- どちらか1案を叩いて弱点を見たい → `/devils-advocate`
- 両方が良くて食い違う、平均でなく一段上で統合したい → `/contradiction-lift`

#### 簡単な見分け方

```
「計画だけ作りたい」              → /collab-planning
「実装して」「実装をチェック」      → /codex-collab
「なぜ？」「原因は？」（未知の原因） → /strong-inference
「これで良いか？」「弱点は？」      → /devils-advocate
「主張をデータで検証/精緻化」      → /dialectic-loop
「2つの良い案を平均でなく止揚」    → /contradiction-lift
```

## 設定

プロジェクト固有の設定は `.claude/codex-collab.local.md` に記述できます。

```markdown
---
sandbox: read-only
language: ja
---

# プロジェクト固有の指示

このプロジェクトでは TypeScript を使用しています。
```

サンプルは [`.claude/codex-collab.local.md.example`](.claude/codex-collab.local.md.example) を参照してください。

### 設定オプション

| オプション | デフォルト | 説明 |
|-----------|-----------|------|
| `workflow` | `auto` | ワークフロー選択 (auto, codex-leads, claude-leads) |
| `model` | (Codexデフォルト) | 使用するモデル (gpt-5.6-sol 等)。省略時は `~/.codex/config.toml` の設定を使用 |
| `sandbox` | `read-only` | サンドボックスモード (read-only, workspace-write, danger-full-access)。codex-leads用 |
| `language` | `en` | レスポンス言語 (en, ja 等) |
| `exchange.enabled` | `true` | Planning exchangeのグローバルキルスイッチ (codex-leads) |
| `exchange.max_iterations` | `3` | Planning exchangeの最大ラウンド数 |
| `exchange.user_confirm` | `on_important` | ユーザー確認タイミング (never, always, on_important) |
| `exchange.history_mode` | `summarize` | 履歴管理方式: full=全履歴保持, summarize=最新2ラウンドのみ全文。**Bash fallback 専用**（MCPモードではスレッドが履歴を保持） |
| `review.enabled` | `true` | Review iterationの有効化 (codex-leads) |
| `review.max_iterations` | `5` | Review iterationの最大ラウンド数（ゴールが明確なので多め） |
| `review.max_verdict_retries` | `3` | verdict が取れない/不明瞭な場合のリトライ回数 |
| `review.user_confirm` | `never` | レビュー時は自動でイテレーション |
| `claude_leads.sandbox` | `workspace-write` | Codex実装用サンドボックス (claude-leads) |
| `claude_leads.consult_codex` | `true` | 計画の壁打ちフェーズ有効化 (claude-leads) |
| `claude_leads.safety_checkpoint` | `stash` | 実装前チェックポイント (stash, wip-commit, none) |
| `claude_leads.review.max_iterations` | `3` | Claudeレビュー修正ループの上限 (claude-leads) |
| `collab_planning.max_iterations` | `3` | 計画レビュー改善サイクルの上限 |
| `collab_planning.user_confirm` | `on_important` | ユーザー確認タイミング (never, always, on_important) |
| `codex.wait_timeout` | `180` | `codex exec` の最大実行時間（秒、max 600）。**Bash fallback 専用**（MCPモードでは無視） |

### 設定の優先順位

```
コマンド引数 > プロジェクト設定 > グローバル設定 > 安全デフォルト
```

## ワークフロー

### Codex-Leads（従来）

Codex が計画・レビュー、Claude が実装するワークフロー。推論に優れたモデルに最適。

```
1. ユーザー: /codex-collab "機能Xを実装して"
2. Claude Code: タスク分析・Codex向けプロンプト作成
3. Codex: 計画作成
4. Claude Code: 計画確認・実装
5. Codex: レビュー（Pass/Fail/Conditional）
6. Claude Code: 修正（必要に応じて）・完了報告
```

### Claude-Leads（新規）

Claude が計画・レビュー、Codex が実装するワークフロー。高速実行向きの軽量モデルに最適。

```
1. ユーザー: /codex-collab "機能Xを実装して"
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

詳細な仕様は `skills/codex-collab/references/` にあります：

- `lightweight-metadata.md` - 軽量メタデータプロトコル仕様
- `planning-prompt.md` - 計画依頼テンプレート
- `review-prompt.md` - レビュー依頼テンプレート
- `deprecated/` - 旧構造化プロトコル（参考用）

## ライセンス

MIT
