# ドキュメントガイド   <!-- omit in toc -->

本フォルダには、Hub-Spoke PoC 環境テンプレートに関する運用ドキュメントを配置しています。

## アーキテクチャ図

[architecture-hubspoke.drawio](../images/architecture-hubspoke.drawio) を draw.io や VS Code の Draw.io 拡張機能で開くと、構成図を確認できます。

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
| 6 | [VM リモート接続ガイド](vm-remote-access.md) | SSH / トンネリング / Jupyter / marimo のセットアップ |
| 7 | [ストレージアカウント ライフサイクル設定手順書](storage-lifecycle.md) | ログストレージのアーカイブ設定 |
| 8 | [共有ストレージ作成手順書](shared-storage.md) | 複数 VM への NFS 共有ストレージマウント |
| 9 | [ログ収集一覧](log-collection-reference.md) | 収集可能なログの種類・取得状況・設定箇所 |
| 10 | [コスト見積もりガイド](cost-estimate.md) | dev / prod 環境の月額概算コスト・削減ヒント |
