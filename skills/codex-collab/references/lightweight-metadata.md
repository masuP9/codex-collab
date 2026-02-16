# Lightweight Metadata Protocol v1.0

Claude Code と Codex 間のイテレーティブな議論をサポートする軽量メタデータ仕様。

## 設計思想

- **本文は自然言語のまま** - LLM の表現力を制限しない
- **メタデータは末尾に付加** - 応答の最後に YAML ブロックとして追加
- **フォールバック可能** - メタデータがなくても本文は読める
- **パース失敗に強い** - 構造化部分のエラーが致命的にならない

## メタデータ形式

応答の末尾に `---` で囲まれた YAML ブロックを付加：

```markdown
（自然言語の応答本文）

...議論や説明...

---
status: continue
verdict: conditional
open_questions:
  - 認証方式の選択
  - エラーハンドリングの粒度
decisions:
  - ファイル構成は提案通り
findings:
  - severity: medium
    message: 入力バリデーションが不足
---
```

## フィールド定義

### 必須フィールド

| フィールド | 型 | 説明 |
|-----------|-----|------|
| `status` | enum | `continue` \| `stop` - 議論を続けるか終了するか |

### オプションフィールド（レビュー用）

| フィールド | 型 | 説明 |
|-----------|-----|------|
| `verdict` | enum | `pass` \| `conditional` \| `fail` - レビュー判定 |
| `findings` | list | 発見事項のリスト |
| `findings[].severity` | enum | `low` \| `medium` \| `high` |
| `findings[].message` | string | 問題の説明 |
| `findings[].suggestion` | string | 修正提案（任意） |

### オプションフィールド（議論用）

| フィールド | 型 | 説明 |
|-----------|-----|------|
| `open_questions` | list[string] | 未解決の質問 |
| `decisions` | list[string] | 合意した決定事項 |
| `blockers` | list[string] | ブロッカー |
| `next_steps` | list[string] | 次のアクション |

## 使用例

### レビュー応答

```markdown
コードを確認しました。

全体的に良い実装ですが、いくつか改善点があります：

1. `validate_input()` で空文字列のチェックが抜けています
2. エラーメッセージがハードコードされています

---
status: stop
verdict: conditional
findings:
  - severity: medium
    message: validate_input() で空文字列チェックが不足
    suggestion: if not input: return False を追加
  - severity: low
    message: エラーメッセージのハードコード
    suggestion: 定数ファイルに移動
---
```

### 議論応答（継続）

```markdown
認証方式について検討しました。

JWT と Session の両方に利点がありますが、
このプロジェクトの要件を考慮すると...

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

### 議論応答（終了）

```markdown
すべての論点が解決しました。

最終的な実装方針：
1. JWT ベースの認証
2. Redis でトークン管理
3. リフレッシュトークンは7日間有効

実装を進めてください。

---
status: stop
decisions:
  - JWT ベースの認証を採用
  - Redis でトークン管理
  - リフレッシュトークン有効期限は7日
next_steps:
  - 認証ミドルウェアの実装
  - トークン発行エンドポイントの作成
---
```

## パース処理

### メタデータ抽出

```bash
# 応答からメタデータブロックを抽出
codex_extract_metadata() {
  local response="$1"
  # 最後の --- ... --- ブロックを抽出
  echo "$response" | tac | sed -n '/^---$/,/^---$/p' | tac | grep -v '^---$'
}

# status フィールドを取得
codex_get_status() {
  local metadata="$1"
  echo "$metadata" | grep '^status:' | sed 's/^status: *//'
}

# verdict フィールドを取得
codex_get_verdict() {
  local metadata="$1"
  echo "$metadata" | grep '^verdict:' | sed 's/^verdict: *//'
}
```

### フォールバック

メタデータがない場合のデフォルト動作：
- `status`: レビューなら `stop`、議論なら `continue`
- `verdict`: 応答に "PASS" / "FAIL" / "CONDITIONAL" があれば抽出

## プロンプトへの組み込み

Codex への指示にメタデータ出力を依頼：

```markdown
## 応答形式

回答の最後に以下の形式でメタデータを付けてください：

\`\`\`
---
status: continue または stop
verdict: pass / conditional / fail（レビューの場合）
open_questions:  # 未解決の質問があれば
  - 質問1
decisions:  # 決定事項があれば
  - 決定1
---
\`\`\`
```

## 旧プロトコルからの移行

`protocol-schema.yaml` の以下の要素は廃止：
- `message_envelope` - 不要（メタデータは応答末尾に埋め込み）
- `task_card` / `result_report` / `action_request` - 自然言語で代替
- `codex_set_buffer` / `codex_respond` 等のbuffer通信 - 不要

保持する概念：
- `status` (旧 `next_action`)
- `verdict` (旧 `review.verdict`)
- `findings` (旧 `review.findings`)
- `open_questions` / `decisions` (新規)
