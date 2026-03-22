# セキュリティエージェントインストール手順書   <!-- omit in toc -->

PoC 環境の VM にセキュリティエージェント（Nessus Agent、Microsoft Defender for Endpoint 等）をインストールする手順です。Azure Bastion 経由の安全な接続で作業します。

## 目次   <!-- omit in toc -->

- [前提条件](#前提条件)
- [1. Bastion トンネルの確立](#1-bastion-トンネルの確立)
- [2. インストーラーの VM への配置](#2-インストーラーの-vm-への配置)
- [3. Nessus Agent インストール](#3-nessus-agent-インストール)
- [4. Microsoft Defender for Endpoint インストール](#4-microsoft-defender-for-endpoint-インストール)
  - [EICAR テストファイルで検証](#eicar-テストファイルで検証)
- [5. その他のエージェント](#5-その他のエージェント)
- [6. セッションの終了](#6-セッションの終了)

## 前提条件

- サブスクリプションに**所有者**ロールが付与されていること
- Azure CLI と以下の拡張機能がインストール済みであること:

  ```bash
  az extension add --name bastion
  az extension add --name ssh
  ```

- 以下のファイルを手元に準備すること:
  - VM 管理者の SSH 秘密鍵
  - Nessus Agent インストーラー（[Tenable ダウンロード](https://www.tenable.com/downloads/nessus-agents)）
  - MDE オンボードパッケージ（[Microsoft 365 Defender ポータル](https://security.microsoft.com/) → 設定 → エンドポイント → オンボーディング）

## 1. Bastion トンネルの確立

ターミナルを開き、以下のコマンドを実行します。

```bash
# Azure にサインイン
az login
az account set --subscription "<サブスクリプション ID>"

# Bastion トンネルを確立（ローカルポート 50026 経由）
az network bastion tunnel \
  --name "bas-<prefix>-japaneast-001" \
  --resource-group "rg-hub-<prefix>-japaneast-001" \
  --target-resource-id "/subscriptions/<サブスクリプション ID>/resourceGroups/rg-spoke-<prefix>-japaneast-001/providers/Microsoft.Compute/virtualMachines/<VM 名>" \
  --resource-port 22 \
  --port 50026
```

以下のメッセージが表示されれば接続完了です:

```
Opening tunnel on port: 50026
Tunnel is ready, connect on port 50026
Ctrl + C to close
```

> **注意**: トンネルは別ターミナルで維持し続けてください。

## 2. インストーラーの VM への配置

**別のターミナル**を開き、`scp` でファイルを転送します。

```bash
# Nessus Agent
scp -P 50026 -i "<秘密鍵パス>" \
  "<Nessus インストーラーのパス>" \
  azureuser@127.0.0.1:~

# MDE オンボードパッケージ
scp -P 50026 -i "<秘密鍵パス>" \
  "<MDE オンボードスクリプトのパス>" \
  azureuser@127.0.0.1:~
```

## 3. Nessus Agent インストール

```bash
# Bastion 経由で VM に SSH 接続
ssh -p 50026 -i "<秘密鍵パス>" azureuser@127.0.0.1

# RHEL/CentOS の場合
sudo rpm -ivh NessusAgent-*.rpm

# エージェントの起動
sudo systemctl start nessusagent

# リンク（Tenable.io に接続する場合）
sudo /opt/nessus_agent/sbin/nessuscli agent link \
  --key=<linking-key> \
  --groups="<グループ名>" \
  --cloud

# UUID の確認（管理者への報告用）
sudo /opt/nessus_agent/sbin/nessuscli agent status
```

## 4. Microsoft Defender for Endpoint インストール

```bash
# Microsoft のリポジトリを追加
sudo yum-config-manager --add-repo=https://packages.microsoft.com/config/rhel/9/prod.repo

# GPG キーのインポート
sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc

# MDE のインストール
sudo yum install -y mdatp

# オンボーディング
sudo python3 MicrosoftDefenderATPOnboardingLinuxServer.py

# ヘルスチェック
mdatp health
```

期待される出力:

```
healthy                                 : true
health_issues                           : []
org_id                                  : <組織 ID>
real_time_protection_enabled            : true
```

### EICAR テストファイルで検証

```bash
# テストファイルをダウンロード（検出されるべき）
curl -o /tmp/eicar.com.txt https://secure.eicar.org/eicar.com.txt

# 検出結果の確認
mdatp threat list
```

> EICAR テストファイルは MDE が正常に稼働していれば自動的に検出・隔離されます。

## 5. その他のエージェント

組織のセキュリティ要件に応じて、以下のエージェントも導入できます:

- **Tanium Client**: エンドポイント管理・パッチ適用
- **UEM ツール**: 統合エンドポイント管理
- **CrowdStrike Falcon**: EDR/XDR

各エージェントのインストール手順は、提供元のドキュメントを参照してください。

## 6. セッションの終了

```bash
# VM から切断
exit

# Bastion トンネルを閉じる（Ctrl + C）

# Azure CLI からログアウト
az logout
```
