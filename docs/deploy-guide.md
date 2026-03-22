# デプロイ手順書   <!-- omit in toc -->

Hub-Spoke PoC 環境のデプロイ手順です。`azd up` による一括デプロイと、Azure CLI による手動デプロイの 2 通りを記載しています。

## 目次   <!-- omit in toc -->

- [前提条件](#前提条件)
  - [Azure 側の準備](#azure-側の準備)
  - [ローカルツール](#ローカルツール)
  - [事前に決めておくこと](#事前に決めておくこと)
- [VM の構成](#vm-の構成)
  - [CPU VM](#cpu-vm)
  - [GPU VM](#gpu-vm)
- [デプロイ方法 1 — azd（推奨）](#デプロイ方法-1--azd推奨)
  - [環境変数の設定](#環境変数の設定)
  - [SSL 証明書の配置（AGW 使用時のみ）](#ssl-証明書の配置agw-使用時のみ)
  - [デプロイ実行](#デプロイ実行)
- [デプロイ方法 2 — Azure CLI](#デプロイ方法-2--azure-cli)
- [パラメータ一覧](#パラメータ一覧)
- [デプロイ後の確認](#デプロイ後の確認)
- [トラブルシューティング](#トラブルシューティング)
  - [リソースプロバイダーの登録エラー](#リソースプロバイダーの登録エラー)
  - [EncryptionAtHost エラー](#encryptionathost-エラー)
  - [VM SKU のキャパシティエラー](#vm-sku-のキャパシティエラー)
  - [GPU VM のクォータエラー](#gpu-vm-のクォータエラー)
  - [デプロイがタイムアウトする](#デプロイがタイムアウトする)

## 前提条件

### Azure 側の準備

- [ ] Azure サブスクリプションに**所有者 (Owner)** ロールがあること
- [ ] Entra ID テナントで**セキュリティ管理者**ロールがあること
- [ ] `Microsoft.Compute/EncryptionAtHost` 機能が登録済みであること

EncryptionAtHost の登録状況は次のコマンドで確認できます。

```bash
az feature show --namespace Microsoft.Compute --name EncryptionAtHost \
  --query "properties.state" -o tsv
```

`NotRegistered` と表示された場合は登録してください。反映まで数分かかります。

```bash
az feature register --namespace Microsoft.Compute --name EncryptionAtHost
az provider register -n Microsoft.Compute
```

### ローカルツール

| ツール | 最低バージョン | 確認コマンド |
|---|---|---|
| Azure CLI | 2.80.0 | `az version` |
| Bicep CLI | 0.35.0 | `az bicep version` |
| Azure Developer CLI (azd) | 1.16.0 | `azd version` |

> Bicep CLI は `az bicep upgrade` で更新できます。azd を使わない場合、azd のインストールは不要です。

```bash
# macOS
brew install azure-cli
brew install azd

# Linux
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
curl -fsSL https://aka.ms/install-azd.sh | bash

# Windows
winget install Microsoft.AzureCLI
winget install Microsoft.Azd
```

### 事前に決めておくこと

デプロイ前に以下の項目を決定してください。

| 項目 | 例 | 備考 |
|---|---|---|
| プレフィックス（英小文字/数字 3-7 桁） | `dev0001` | リソース名に使用 |
| VM 台数・SKU | CPU VM 1 台 `Standard_D4s_v6` | パターン: 1=CPU / 2=GPU / 3=両方 |
| Microsoft Foundry | `eastus2`, `gpt-5-mini` | 不要なら `ENABLE_FOUNDRY=false` |
| 接続元 IP | `203.0.113.0/24` | 運用者とエンドユーザーの 2 種類 |
| Application Gateway | `.example.com` + SSL 証明書 | 不要なら `ENABLE_APP_GATEWAY=false` |
| アラート通知先 | `ops@example.com` | |

## VM の構成

このテンプレートでは 2 種類の VM を選択できます。`vmPattern` パラメータで制御します。

### CPU VM

OS は RHEL 9.4、SSH 鍵認証のみ。cloud-init でデータディスクのフォーマットと OS ディスク拡張を自動実行します。

| パーティション | 容量 |
|---|---|
| / (root) | 15 GB |
| /usr | 20 GB |
| /tmp | 10 GB |
| /home | 15 GB |
| /var | 30 GB |
| /datadrive | パラメータ指定（デフォルト 512 GB） |

### GPU VM

CPU VM の構成に加え、以下のミドルウェアを cloud-init で自動インストールします。

| ミドルウェア | バージョン |
|---|---|
| CUDA Driver | 550.90.07 |
| CUDA Toolkit | 12.4 |
| NVIDIA Container Toolkit | 1.17.4 |
| Podman | 4.9.4 |
| Python | 3.14 |

`/home` は LLM モデル格納を想定して 1.0 TB に拡張されます。データディスクのデフォルトは 1536 GB です。

## デプロイ方法 1 — azd（推奨）

```bash
git clone https://github.com/<your-org>/azure-poc-hub-spoke.git
cd azure-poc-hub-spoke
az login
```

### 環境変数の設定

```bash
azd init

# 必須
azd env set AZURE_PREFIX "dev0001"
azd env set AZURE_LOCATION "japaneast"
azd env set OPERATOR_ALLOW_IP "203.0.113.0/24"
azd env set CUSTOMER_ALLOW_IP "198.51.100.0/24"

# アラート
azd env set ALERT_EMAIL "ops@example.com"

# Application Gateway を使う場合
azd env set ENABLE_APP_GATEWAY "true"
azd env set DOMAIN ".example.com"
azd env set SSL_PASSWORD "<pfx-password>"
```

全環境変数の一覧は [パラメータ一覧](#パラメータ一覧) を参照してください。

### SSL 証明書の配置（AGW 使用時のみ）

```bash
mkdir -p infra/certs
cp /path/to/your-cert.pfx infra/certs/server.pfx
```

証明書の発行方法は [SSL 証明書発行手順書](ssl-certificate-issuance.md) を参照してください。

### デプロイ実行

```bash
azd up
```

`azd up` は以下の 3 ステップを自動実行します。

1. **preprovision** — SSH 鍵生成、プリンシパル ID 取得、リソースプロバイダー登録
2. **provision** — Bicep テンプレートのデプロイ（サブスクリプションスコープ）
3. **postprovision** — VNet Flow Log 作成、SSL 証明書の Key Vault 登録

## デプロイ方法 2 — Azure CLI

azd を使わず Azure CLI だけでデプロイする場合の手順です。

```bash
# SSH 鍵の生成
mkdir -p infra/keys
ssh-keygen -t rsa -b 4096 -N "" -f infra/keys/id_rsa

# What-If で変更内容を事前確認
az deployment sub what-if \
  --location japaneast \
  --template-file infra/main.bicep \
  --parameters infra/parameters/dev.bicepparam \
  --parameters sshPublicKey="$(cat infra/keys/id_rsa.pub)" \
  --parameters principalId="$(az ad signed-in-user show --query id -o tsv)"

# 問題なければデプロイ
az deployment sub create \
  --location japaneast \
  --template-file infra/main.bicep \
  --parameters infra/parameters/dev.bicepparam \
  --parameters sshPublicKey="$(cat infra/keys/id_rsa.pub)" \
  --parameters principalId="$(az ad signed-in-user show --query id -o tsv)"
```

パラメータを変更する場合は `dev.bicepparam` をコピーして編集してください。

```bash
cp infra/parameters/dev.bicepparam infra/parameters/my-env.bicepparam
# 編集後、--parameters で指定
```

## パラメータ一覧

| パラメータ | 説明 | デフォルト |
|---|---|---|
| `prefix` | リソース命名プレフィックス (3-7 桁) | *(必須)* |
| `location` | デプロイ先リージョン | `japaneast` |
| `vmPattern` | 1:CPU / 2:GPU / 3:両方 | `3` |
| `cpuvmNumber` / `gpuvmNumber` | VM 台数 | `1` / `1` |
| `cpuvmSku` | CPU VM の SKU | `Standard_D8as_v5` |
| `gpuvmSku` | GPU VM の SKU | `Standard_NC24ads_A100_v4` |
| `cpuvmDataDiskSize` | CPU VM データディスク (GB) | `512` |
| `gpuvmDataDiskSize` | GPU VM データディスク (GB) | `1536` |
| `sshPublicKey` | SSH 公開鍵 | *(必須)* |
| `principalId` | デプロイ実行者のプリンシパル ID | *(必須)* |
| `enableFoundry` | Microsoft Foundry の有効/無効 | `true` |
| `foundryLocation` | AI Services リージョン | `eastus2` |
| `enableAppGateway` | Application Gateway の有無 | `false` |
| `domain` | ドメイン名（AGW 使用時） | `.example.com` |
| `enableBackup` | Azure Backup の有無 | `true` |
| `enableVmAutoStartStop` | VM 自動停止の有効/無効 | `true` |
| `vmStopTime` | VM 停止時刻 (HHmm) | `1800` |
| `enableDefender` | Defender for Cloud | `false` |
| `enableVmMonitoring` | VM 性能監視 (AMA + アラート) | `false` |
| `enableWorm` | ストレージ不変性ポリシー (WORM) | `false` |
| `wormRetentionDays` | WORM 保持期間（日） | `7` |
| `alertEmail` | アラート通知先 | `ops@example.com` |

> azd 経由で設定する場合の環境変数名は [README.md](../README.md#パラメータ一覧) を参照してください。

## デプロイ後の確認

```bash
# デプロイしたリソースの一覧
az resource list --resource-group rg-hub-<prefix>-japaneast-001 -o table
az resource list --resource-group rg-spoke-<prefix>-japaneast-001 -o table

# Bastion 経由で VM に接続できるか確認
az network bastion tunnel \
  --name "bas-<prefix>-japaneast-001" \
  --resource-group "rg-hub-<prefix>-japaneast-001" \
  --target-resource-id "$(az vm show -g rg-spoke-<prefix>-japaneast-001 -n vm-cpu-<prefix>-japaneast-001 --query id -o tsv)" \
  --resource-port 22 --port 50022
```

接続方法の詳細は [VM リモート接続ガイド](vm-remote-access.md) を参照してください。

## トラブルシューティング

### リソースプロバイダーの登録エラー

`MissingRegistrationForType` が出た場合、該当プロバイダーを登録してください。`azd up` 経由であれば preprovision で自動登録されます。

```bash
az provider show -n Microsoft.CognitiveServices --query "registrationState"
az provider register --namespace Microsoft.CognitiveServices
```

### EncryptionAtHost エラー

v6 世代の VM SKU（`Standard_D4s_v6` 等）では `EncryptionAtHost` 機能の登録が必須です。[前提条件](#azure-側の準備)の手順で登録してください。

### VM SKU のキャパシティエラー

`SkuNotAvailable` が出た場合、そのリージョンで SKU の在庫が不足しています。別の SKU またはリージョンに変更してください。

```bash
# japaneast で利用可能な D シリーズの確認
az vm list-sizes --location japaneast -o tsv | grep -E "Standard_D[0-9]+s_v[56]"
```

### GPU VM のクォータエラー

GPU SKU にはサブスクリプション単位のクォータ制限があります。`QuotaExceeded` が出る場合はクォータ引き上げを申請してください。

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

### デプロイがタイムアウトする

GPU VM の cloud-init（CUDA ドライバのインストール等）には 15-30 分かかります。`az deployment sub show` でデプロイのステータスを確認し、まだ進行中であれば待ってください。

```bash
az deployment sub show --name deploy-spoke --query "properties.provisioningState" -o tsv
```
