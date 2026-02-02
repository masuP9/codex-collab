# コードベース簡素化計画

Created: 2026-02-03
Status: 計画立案完了（実装待ち）

## 概要

codex-collab プラグインのレガシーコードを削除し、コードベースをシンプルにする計画。

## 調査結果（Claude Code + Codex 協調調査）

### 発見された問題

#### 1. 大量の未使用ヘルパー関数
- `codex-helpers.sh`: 67関数定義、**コマンドファイルからの呼び出し 0**
- コマンドファイルは `source` しているが、実際にはインライン実装を使用
- 約 **1,400行** の完全に使われていないコード

#### 2. 深刻なコード重複（11箇所のインラインフォールバック）
| 機能 | 重複箇所数 |
|------|-----------|
| 言語指示検出 | 2箇所 |
| ペイン検出/検証 | 3箇所 |
| プロンプト送信 | 3箇所 |
| 完了検出（hash+idle） | 4箇所 |

#### 3. レガシー関数群
- **signal/evented ベースの wait 関数**: 9個（約300行）- 使われていない
- **session/state/buffer 管理関数**: 22個（約270行）- 使われていない
- **廃止プロトコルスキーマファイル**: 3個（約11KB）

#### 4. アーキテクチャの不整合
- ドキュメント: 「ヘルパー関数を使用」と記載
- 実態: コマンドファイルがインラインで再実装

### ファイルサイズ分析

| ファイル | 行数 | サイズ | 問題 |
|----------|------|--------|------|
| codex-helpers.sh | 2,687行 | 88KB | 67関数中0が使用される |
| collab-codex.md | 1,085行 | 40KB | 500行以上がインライン重複 |
| collab-codex-attach.md | 559行 | 20KB | 150行以上がインライン重複 |
| strong-inference.md | 873行 | 28KB | 中程度の複雑さ |

### 技術的負債の概算

- **未使用ヘルパー関数**: ~1,400行
- **重複インラインコード**: ~600行
- **レガシー signal/evented 関数**: ~300行
- **未使用 state/session 抽象化**: ~270行
- **合計**: **~2,000行以上** の削減可能なコード

## 推奨アプローチ

### Option C: ハイブリッド（推奨）

Codex との協議により、以下の理由で **Option C: ハイブリッド** を採用:

1. **既存コマンドにインライン実装が多く、完全なヘルパー移行はコスト高**
2. **重複が深刻なので、コア機能だけ共通化して削除対象を明確化するのが安全**
3. **影響範囲を段階的に抑えられる**

### 方針の詳細

- **核となる共通機能のみヘルパー化**
  - ペイン検出 (`codex_find_pane`)
  - プロンプト送信 (`codex_send_prompt_file`, `codex_send_prompt_chunked`)
  - 完了待機 (`codex_wait_completion`)
  - 出力キャプチャ (`codex_capture_output`)
  - ハッシュ計算 (`codex_hash_content`)

- **シンプルな機能はインラインで保持**
  - 言語指示生成
  - セッション状態チェック
  - 一時ファイル作成

## 削除対象リスト

### Phase 1: 明らかに不要なレガシー関数

```
# signal/evented 系（約300行）
codex_setup_evented_wait()      # polling で代替済み
codex_wait_evented_signal()     # 使用されていない
codex_cleanup_evented_wait()    # 使用されていない
codex_evented_session_dir()     # 使用されていない
# + 関連する5つのサブ関数

# session/state/buffer 管理（約270行）
codex_init_session()            # 使用されていない
codex_save_session_state()      # 使用されていない
codex_load_session_state()      # 使用されていない
codex_clear_session()           # 使用されていない
# + 関連する18つのサブ関数
```

### Phase 2: 廃止プロトコルファイル

```
references/protocol/file-response-schema.json   # 廃止
references/protocol/marker-protocol.json        # 廃止
references/protocol/legacy-exec-mode.md         # 廃止（もし存在すれば）
```

### Phase 3: 重複コードの統合

コマンドファイル内のインラインフォールバックを削除し、ヘルパー関数を実際に呼び出すように変更:

```markdown
# Before (collab-codex.md)
if type codex_wait_completion &>/dev/null; then
  codex_wait_completion "$CODEX_PANE" "$END_MARKER" "$BEFORE_HASH"
else
  # 50行のインラインフォールバック...
fi

# After
codex_wait_completion "$CODEX_PANE" "$END_MARKER" "$BEFORE_HASH"
```

## 保持すべきもの

| 関数/機能 | 理由 |
|-----------|------|
| `codex_find_pane()` | 全コマンドで必要 |
| `codex_verify_pane()` | ペイン有効性確認に必要 |
| `codex_send_prompt_file()` | 長いプロンプト送信の主要手段 |
| `codex_send_prompt_chunked()` | 代替送信手段として有用 |
| `codex_wait_completion()` | 完了検出の主要手段 |
| `codex_capture_output()` | 出力キャプチャに必要 |
| `codex_hash_content()` | 変更検出に必要 |
| `codex_check_tmux()` | tmux 環境チェックに必要 |
| `codex_ensure_tmp_dir()` | 一時ディレクトリ管理に必要 |
| `codex_get_language_directive()` | 言語設定に必要 |

## リファクタリング手順

### Step 1: 関数使用実態の確定
```bash
# ヘルパー関数呼び出し箇所を洗い出す
rg "codex_\w+" commands/ scripts/ --stats
```

### Step 2: 共通化対象の決定
- pane検出/送信/待機など中核だけ残す
- 使用頻度と重複度を考慮

### Step 3: コマンド側の整理
- インラインフォールバックを削除
- ヘルパー関数を実際に呼び出す

### Step 4: 未使用ヘルパー削除
- 使用箇所ゼロの関数を削除
- 関連するコメント・ドキュメントも更新

### Step 5: ドキュメント整合
- CLAUDE.md のヘルパー関数一覧を更新
- 「ヘルパー利用」と実態を一致させる

### Step 6: 回帰チェック
- tmux モードでの動作確認
- 非 tmux（wt/inline）モードでの動作確認
- 短文/長文プロンプトの送信テスト

## リスクと対策

| リスク | 対策 |
|--------|------|
| 想定外の利用箇所が存在 | `rg` と動的テストで確認 |
| 共通化による挙動差 | 段階的導入（1コマンドずつ） |
| ドキュメントの不整合 | 最終ステップで更新必須 |
| インラインフォールバック削除後の動作不良 | ヘルパーが `source` されることを保証 |

## 期待される効果

### コード量
- **Before**: ~4,000行（codex-helpers.sh + コマンドファイル）
- **After**: ~1,500-2,000行（推定）
- **削減**: ~50%

### 保守性
- 単一の実装パス（ヘルパー関数）
- バグ修正が1箇所で済む
- ドキュメントと実装が一致

### 理解しやすさ
- 不要な関数がなくなり、コードベースが見通しやすくなる
- 新規開発者のオンボーディングが容易に

## 参照

- 調査ログ: `tmp/strong-inference/20260202-235408-19737.md`
- Codex 応答: `tmp/codex-simplify-plan.txt`
- 関連 PR: (実装時に記載)

---

**Decisions (Codex との協議結果)**:
- Option C（ハイブリッド）を採用
- まず使用実態の可視化 → 共通化 → 未使用削除の順で進める
