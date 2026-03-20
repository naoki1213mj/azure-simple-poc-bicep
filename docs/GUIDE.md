# ドキュメントガイド   <!-- omit in toc -->

本フォルダには、Hub-Spoke PoC 環境テンプレートに関する運用ドキュメントを配置しています。

## アーキテクチャ図

[architecture.drawio](architecture.drawio) を draw.io や VS Code の Draw.io 拡張機能で開くと、2パターンの構成図を確認できます。

| タブ | 内容 |
|---|---|
| パターン① AGW あり | Application Gateway (WAF v2) による外部公開構成 |
| パターン② Bastion のみ | Bastion 経由のアクセスのみ（閉じた構成） |

## ドキュメント一覧

| # | ドキュメント | 内容 |
|---|---|---|
| 1 | [デプロイ手順書](deploy-guide.md) | azd / Azure CLI を使った環境構築手順 |
| 2 | [環境削除手順書](teardown-guide.md) | PoC 環境を安全に削除する手順 |
| 3 | [DNS レコード登録手順書](dns-record-guide.md) | Azure DNS Zone への A レコード追加手順 |
| 4 | [SSL 証明書発行手順書](ssl-certificate-issuance.md) | 自己署名 / Let's Encrypt / 商用 CA での証明書発行 |
| 5 | [SSL 証明書更新手順書](ssl-certificate-renewal.md) | Key Vault + Application Gateway の SSL 証明書更新 |
| 6 | [セキュリティエージェントインストール手順書](security-agent-install.md) | Nessus / MDE / Tanium 等のエージェント導入手順 |
| 7 | [VM リモート接続ガイド](vm-remote-access.md) | SSH / トンネリング / Jupyter / marimo のセットアップ |
| 8 | [ストレージアカウント ライフサイクル設定手順書](storage-lifecycle.md) | ログストレージのアーカイブ設定 |
| 9 | [共有ストレージ作成手順書](shared-storage.md) | 複数 VM への NFS 共有ストレージマウント |
| 10 | [ログ収集一覧](log-collection-reference.md) | 収集可能なログの種類・取得状況・設定箇所 |
| 11 | [コスト見積もりガイド](cost-estimate.md) | dev / prod 環境の月額概算コスト・削減ヒント |

## 付録（参考資料）

| # | ファイル | 内容 |
|---|---|---|
| 1 | PoC環境テンプレート_Azure_構築後確認項目.xlsx | デプロイ後の設定確認チェックリスト |
| 2 | PoC環境テンプレート_ログ取得一覧.xlsx | ログ収集対象一覧 |
| 3 | PoC環境テンプレート_概算見積もり.xlsx | 概算コスト見積もり参考例 |
| 4 | PoC環境テンプレート_構成図.pptx | アーキテクチャ構成図 |
