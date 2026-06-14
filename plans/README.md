# Implementation Plans

improve スキルによる監査（2026-06-11、commit `f5abf51` 時点）から生成。
特記なき限り下表の順に実行すること。各 executor はプランを最後まで読み、
STOP conditions を守り、完了時に自分の行を更新すること。

> 対話セッションではなかったため、レバレッジ上位 5 件を既定としてプラン化した。
> 取捨選択はメンテナーが本表の Status を REJECTED に変えることで行える。

## Execution order & status

| Plan | Title | Priority | Effort | Depends on | Status |
|------|-------|----------|--------|------------|--------|
| 001 | CI に shellcheck を追加し既存指摘をトリアージ | P1 | S–M | — | DONE（2026-06-12 executor 実行・レビュー承認済み。ブランチ `feat/ci-shellcheck`、コミット `9d542f8`。2026-06-12 マージ済み。CI コマンドはプラン記載から `--source-path=SCRIPTDIR -x` 付きに正当な逸脱あり） |
| 002 | PreToolUse フックにテストを追加 | P1 | S | — | DONE（2026-06-12 executor 実行・レビュー承認済み。ブランチ `feat/hook-tests`、コミット `7eab2c1`。2026-06-12 マージ済み。11ケース全パス、誤検知 characterization 含む） |
| 003 | プラグイン整合性 lint（version 同期・bash ブロック検証） | P2 | M | — | DONE（2026-06-12 executor 実行 + REVISE 1回（/tmp 固定パス修正）・レビュー承認済み。ブランチ `feat/plugin-consistency-lints`、コミット `21db6d9`+`5b13463`。2026-06-12 マージ済み） |
| 004 | セッション状態 JSON と ANSI 除去の堅牢化 | P2 | M | —（001 の後が望ましい） | DONE（2026-06-12 executor 実行 + REVISE 2回（テスト強化）・レビュー承認済み。ブランチ `fix/session-state-hardening`、コミット `8a9d9e1`+`7b9fc35`+`ee8175f`。2026-06-12 マージ済み。旧コードで fail / 新コードで pass する regression guard を実証済み） |
| 005 | リポジトリ衛生（.gitignore タイポ・stale 文書・テスト手順） | P3 | S | — | DONE（2026-06-12 executor 実行・レビュー承認済み。ブランチ `fix/repo-hygiene`、コミット `b7e8e4f`（v0.32.1）、PR #60。2026-06-12 マージ済み。逸脱なし、done criteria 全件をレビュアーが再検証済み） |
| 006 | フック関数名検出の実行位置アンカー化（誤検知解消） | P3 | S | 002 (DONE) | DONE（2026-06-12 executor 実行・レビュー承認済み。初版 `fix/hook-pattern-precision`（`c7f2078`、v0.32.1）は 001–005 マージ後の main と版番衝突したため、main `179bf5a` 起点で `fix/hook-pattern-precision-v2`（`cd9218f`、v0.32.2）に積み直し済み、PR #61。機能差分は承認版と同一であることをレビュアーが diff で確認、全ゲート再検証済み（hook 17/17・helpers 99/99・lint PASS）。2026-06-12 マージ済み（`cebe35e`）） |

| 007 | フック検出対象の縮小（副作用持ち 4 関数 + マーカー厳格化 + ソフトガード再定義） | P3 | S–M | 006 (DONE・マージ済み) | DONE（2026-06-12 executor 実行・レビュー承認済み。ブランチ `feat/hook-scope-reduction`、コミット `d1feecc`（v0.33.0）、PR #62（CI green）。done criteria 全件をレビュアーが worktree で再検証済み（hook 22/22・helpers 99/99・lint PASS・広域パターン削除 grep 0・docs 2 ファイル同期・Sunset criteria 追加）。逸脱 1 件（done criteria の grep を満たすためのコメント文言調整）は文書化済みで妥当。2026-06-14 マージ済み（`f70cdb2`）） |

Status values: TODO | IN PROGRESS | DONE | BLOCKED (with one-line reason) | REJECTED (with one-line rationale)

## Dependency notes

- ハード依存はない。001 を最初に推奨する理由は、以降のプラン（特に 004 のシェル変更）が自動的に shellcheck のゲートを通るため。
- 006 は 002 のテスト（DONE・マージ済み）を前提とし、Plan 002 の Maintenance notes に記載された「ケース 11 の期待値反転」手順を実行するもの。発端は 2026-06-12 に実測された誤検知 3 件（PR #56 本文・grep 調査・Plan 004 のコミットメッセージ）。
- 各プランがそれぞれバージョンをバンプする（リポジトリの 1 PR = 1 バンプ慣行に合わせた）。連続実行時は「現行値から +1」とプランに明記してあるので衝突しない。
- 003 と 004 は commands/*.md と scripts/codex-helpers.sh で対象が分かれており並行可能。
- 007 は 2026-06-12 の Devil's Advocate レビュー（tmp/devils-advocate/20260612-120332-24936.md、verdict: CONDITIONAL）の承認条件を実装するもの。**PR #61（Plan 006）のマージが前提**（Step 0 で検証）。マイナーバンプ（0.33.0）。

## Findings considered and rejected

再監査の手間を省くための記録（監査サブエージェントの報告をアドバイザーが実コードで検証した結果）:

- **フック「バイパス」（コマンド文字列に CODEX_SKILL_CONTEXT=1 を含めると素通り）**: 仕様どおり。このフックは LLM をスキルに誘導するガードレールであり、セキュリティ境界ではない（docs/bash-usage.md 参照）。Plan 002 の Maintenance notes にも明記。
- **`codex_get_field` の regex インジェクション**: field 名は全呼び出し箇所でハードコードされたリテラル（"status"/"verdict" 等）であり、外部入力が入る経路がない。堅牢化の価値はあるが優先度なし。
- **`codex_infer_verdict` の exit code 契約違反**: 誤報。コードはコメントどおり 0/1 を返し、`v=$(codex_infer_verdict ...)` の代入は exit status を保持する。
- **`codex_sanitize_task_id` の空チェック漏れ（save_thread/load_thread）**: 誤報。3 関数とも `[ -z "$task_id" ] && return 1` 相当のチェックが存在する（codex-helpers.sh:538-541, 615-617, 641-644）。
- **「ヘルパー関数 15 個が未使用」**: ほぼ誤報。grep で確認した結果、大半は commands/skills から、または codex-helpers.sh 内部から参照されている。真に未参照の候補は `codex_generate_signal` 程度で、削除価値が小さい。
- **README のモデル名（gpt-5, codex-mini, o3, o4-mini）が架空**: 誤報。いずれも実在する OpenAI モデル。
- **claude-leads ワークフローが未実装**: 誤報。commands/codex-collab.md:846-1362（Step 2c、Thread B/C 配線）に実装済み。auto が codex-leads 固定なのはタイムアウト問題による文書化済みの意図的決定（同:154）。
- **commands/*.md と skills/*/SKILL.md の「乖離」**: 役割分担による設計（SKILL.md = トリガー定義、commands/*.md = 実装手順）。同期義務はない。
- **markdown 再パースのパフォーマンス**: 実測根拠なし。実害が示されるまで対応不要。
- **コマンド md 全体の統合テストハーネス（mock MCP 含む）**: 価値はあるが L 効目に対し、まず Plan 003 の構文 lint で大半の事故を S 効目で防げる。lint 運用後も事故が続く場合に再検討。
- **collab-planning と codex-collab の計画フェーズ統合 / マルチ CLI トランスポート抽象化**: 方向性の選択肢としてメンテナーに提示済み（監査レポート参照）。設計判断が必要なためプラン化は見送り。
