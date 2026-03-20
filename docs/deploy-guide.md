# デプロイ手順書   <!-- omit in toc -->

Hub-Spoke PoC 環境を Azure Developer CLI (`azd`) または Azure CLI でデプロイする手順です。

## 目次   <!-- omit in toc -->

- [前提条件チェックリスト](#前提条件チェックリスト)
- [構成](#構成)
  - [構成パターン](#構成パターン)
  - [CPU VM と GPU VM の構成](#cpu-vm-と-gpu-vm-の構成)
- [事前準備](#事前準備)
- [1. azd を使ったデプロイ（推奨）](#1-azd-を使ったデプロイ推奨)
- [2. Azure CLI を使ったデプロイ](#2-azure-cli-を使ったデプロイ)
- [3. パラメータ一覧](#3-パラメータ一覧)
- [4. トラブルシューティング](#4-トラブルシューティング)

## 前提条件チェックリスト

> チェックボックスは未確認 (□) を示します。要件を満たしたら ✔ を入れてください。

### 基盤
- [ ] **Microsoft Entra テナント**が準備済みであること
- [ ] **Azure サブスクリプション**が準備済みであること

### 権限
- [ ] Entra ID で **セキュリティ管理者** ロールが付与済みであること
- [ ] サブスクリプションで **所有者 (Owner)** ロールが付与済みであること

### ローカルツール
- [ ] **Azure CLI** v2.72.0 以上がインストール済みであること
- [ ] **Azure Developer CLI (azd)** v1.10.0 以上がインストール済みであること（azd デプロイの場合）

### 事前確認項目

| 区分 | 確認事項 | 決定例 |
|------|----------|--------|
| 命名 | プレフィックス名（英小文字/数字 3-7 桁） | `dev0001` |
| VM | CPU VM / GPU VM の台数・SKU・Data ディスクサイズ | CPU VM 1 台 |
| AI Foundry | 利用有無・リージョン・モデル | あり, `eastus2`, `gpt-5` |
| 接続元 IP | 運用者/エンドユーザーのグローバル IP | `203.0.113.0/24` |
| 通知先 | アラート送信先メールアドレス | `ops@example.com` |
| Application Gateway | 利用有無・ドメイン・SSL 証明書 | あり, `.example.com` |
| バックアップ | Azure Backup 利用有無 | あり |

## 構成

### 構成パターン

| パターン | 説明 |
|----------|------|
| パターン① | Application Gateway (WAF v2) を使用してアプリを外部公開する構成 |
| パターン② | Bastion 経由のみでアクセスする閉じた構成 |

### CPU VM と GPU VM の構成

**CPU VM** — アプリケーション実行用

| # | パーティション | ディスク容量 |
|---|---|---|
| 1 | / (root) | 15 GB |
| 2 | /usr | 20 GB |
| 3 | /tmp | 10 GB |
| 4 | /home | 15 GB |
| 5 | /var | 30 GB |
| 6 | /datadrive | パラメータで指定したサイズ |

**GPU VM** — LLM/CUDA ワークロード用

| # | ミドルウェア | バージョン |
|---|---|---|
| 1 | CUDA Driver | 550.90.07 |
| 2 | CUDA Toolkit | 12.4 |
| 3 | NVIDIA Container Toolkit | 1.17.4 |
| 4 | Podman | 4.9.4 |
| 5 | Python | 3.12 |

| # | パーティション | ディスク容量 |
|---|---|---|
| 1 | / (root) | 15 GB |
| 2 | /usr | 20 GB |
| 3 | /tmp | 10 GB |
| 4 | /home | 1.0 TB |
| 5 | /var | 30 GB |
| 6 | /datadrive | パラメータで指定したサイズ |

## 事前準備

### Azure CLI のインストール

```bash
# macOS
brew install azure-cli

# Ubuntu/Debian
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Windows (winget)
winget install Microsoft.AzureCLI
```

### Azure Developer CLI のインストール

```bash
# macOS
brew install azd

# Linux
curl -fsSL https://aka.ms/install-azd.sh | bash

# Windows (winget)
winget install Microsoft.Azd
```

### Azure へのログイン

```bash
az login
az account set --subscription "<サブスクリプション ID>"
```

## 1. azd を使ったデプロイ（推奨）

### 1-1. リポジトリのクローン

```bash
git clone https://github.com/<your-org>/azure-poc-hub-spoke.git
cd azure-poc-hub-spoke
```

### 1-2. 環境変数の設定

```bash
azd init

# 必須パラメータ
azd env set AZURE_PREFIX "dev0001"
azd env set AZURE_LOCATION "japaneast"

# ネットワーク
azd env set OPERATOR_ALLOW_IP "203.0.113.0/24"
azd env set CUSTOMER_ALLOW_IP "198.51.100.0/24"

# アラート
azd env set ALERT_EMAIL "ops@example.com"

# Application Gateway（不要な場合は false）
azd env set ENABLE_APP_GATEWAY "true"
azd env set DOMAIN ".example.com"
azd env set SSL_PASSWORD "<pfx-password>"
```

### 1-3. SSL 証明書の配置（Application Gateway 使用時）

```bash
mkdir -p infra/certs
cp /path/to/your-cert.pfx infra/certs/server.pfx
```

### 1-4. デプロイ実行

```bash
azd up
```

以下が自動実行されます:
1. **preprovision**: SSH 鍵生成、乱数 ID 生成、リソースプロバイダー登録
2. **provision**: Bicep テンプレートのデプロイ
3. **postprovision**: VNet Flow Log 作成、SSL 証明書の Key Vault 登録

## 2. Azure CLI を使ったデプロイ

### 2-1. SSH 鍵の生成

```bash
mkdir -p infra/keys
ssh-keygen -t rsa -b 4096 -N "" -f infra/keys/id_rsa
```

### 2-2. パラメータファイルの準備

```bash
# dev 環境の場合
cp infra/parameters/dev.bicepparam infra/my-deploy.bicepparam
# my-deploy.bicepparam を編集して値を設定
```

### 2-3. デプロイ実行

```bash
az deployment sub create \
  --location japaneast \
  --template-file infra/main.bicep \
  --parameters infra/my-deploy.bicepparam
```

## 3. パラメータ一覧

詳細なパラメータ一覧は [README.md](../README.md#パラメータ一覧) を参照してください。

### 主要パラメータ（抜粋）

| パラメータ | 説明 | デフォルト |
|---|---|---|
| `prefix` | リソース命名プレフィックス (3-7桁) | *(必須)* |
| `location` | デプロイ先リージョン | `japaneast` |
| `vmPattern` | 1:CPU / 2:GPU / 3:両方 | `3` |
| `cpuvmNumber` | CPU VM 台数 | `1` |
| `gpuvmNumber` | GPU VM 台数 | `1` |
| `enableFoundry` | AI Foundry の有効/無効 | `true` |
| `enableAppGateway` | Application Gateway の有無 | `false` |
| `enableBackup` | Azure Backup の有無 | `true` |

## 4. トラブルシューティング

### リソースプロバイダーの登録エラー

一部のリソースプロバイダーが未登録の場合、デプロイに失敗します。

```bash
# 状態確認
az provider show -n Microsoft.CognitiveServices --query "registrationState"

# 登録
az provider register --namespace Microsoft.CognitiveServices
```

### GPU VM のクォータエラー

GPU VM の SKU にはクォータ制限があります。

```bash
# 現在のクォータ確認
az quota usage list \
  --scope "/subscriptions/<sub-id>/providers/Microsoft.Compute/locations/japaneast" \
  --query "[?contains(name, 'NCADS')]" -o table

# クォータ引き上げ申請
az quota update \
  --resource-name "StandardNCADSA100v4Family" \
  --scope "/subscriptions/<sub-id>/providers/Microsoft.Compute/locations/japaneast" \
  --limit-object value=24 \
  --resource-type dedicated
```

### What-If で事前確認

デプロイ前に変更内容を確認できます。

```bash
az deployment sub what-if \
  --location japaneast \
  --template-file infra/main.bicep \
  --parameters infra/parameters/dev.bicepparam
```
