# 環境削除手順書   <!-- omit in toc -->

Hub-Spoke PoC 環境の削除手順です。リソースロック・バックアップ・論理削除などの依存があるため、記載順に実行してください。

## 目次   <!-- omit in toc -->

- [前提条件](#前提条件)
- [azd を使った削除（推奨）](#azd-を使った削除推奨)
- [手動削除](#手動削除)
  - [0. リソースロックの解除](#0-リソースロックの解除)
  - [1. Recovery Services コンテナーの保護停止](#1-recovery-services-コンテナーの保護停止)
  - [2. AI Services モデルの削除](#2-ai-services-モデルの削除)
  - [3. Automation スケジュールの削除](#3-automation-スケジュールの削除)
  - [4. リソースグループの削除](#4-リソースグループの削除)
  - [5. VNet Flow Log の削除](#5-vnet-flow-log-の削除)
  - [6. サブスクリプションレベルのデプロイ削除](#6-サブスクリプションレベルのデプロイ削除)
  - [7. 論理削除リソースの消去](#7-論理削除リソースの消去)
- [付録: WORM 有効時のストレージ削除](#付録-worm-有効時のストレージ削除)

## 前提条件

- サブスクリプションの**所有者 (Owner)** ロール

## azd を使った削除（推奨）

```bash
azd down
```

`azd down` ではリソースロック付きリソースと論理削除リソースの消去は行われません。削除後、以下の手動手順で残存リソースを確認してください。

## 手動削除

以下、`<prefix>` はデプロイ時に指定したプレフィックス（例: `dev0001`）に読み替えてください。

### 0. リソースロックの解除

VNet / Bastion / DNS Zone / Key Vault / Storage / Log Analytics にリソースロックが設定されています。リソースグループを削除する前にロックを解除してください。

```bash
# Spoke RG のロック一覧
az lock list --resource-group "rg-spoke-<prefix>-japaneast-001" -o table

# 各ロックを削除
az lock delete --name "lock-vnet-spoke" --resource-group "rg-spoke-<prefix>-japaneast-001"
az lock delete --name "lock-law" --resource-group "rg-spoke-<prefix>-japaneast-001"
az lock delete --name "lock-kv" --resource-group "rg-spoke-<prefix>-japaneast-001"
az lock delete --name "lock-st" --resource-group "rg-spoke-<prefix>-japaneast-001"

# Hub RG のロック一覧
az lock list --resource-group "rg-hub-<prefix>-japaneast-001" -o table

# 各ロックを削除
az lock delete --name "lock-vnet-hub" --resource-group "rg-hub-<prefix>-japaneast-001"
az lock delete --name "lock-bastion" --resource-group "rg-hub-<prefix>-japaneast-001"
az lock delete --name "lock-pdz-blob" --resource-group "rg-hub-<prefix>-japaneast-001"
az lock delete --name "lock-pdz-cog" --resource-group "rg-hub-<prefix>-japaneast-001"
az lock delete --name "lock-pdz-vault" --resource-group "rg-hub-<prefix>-japaneast-001"
```

Azure Portal の場合は、各リソース → **設定** → **ロック** から削除できます。

### 1. Recovery Services コンテナーの保護停止

`enableBackup = true` でデプロイした場合のみ必要です。

```bash
VAULT_NAME="rsv-<prefix>-japaneast-001"
RG="rg-spoke-<prefix>-japaneast-001"

# 論理的な削除を無効化
az backup vault backup-properties set \
  --name "$VAULT_NAME" --resource-group "$RG" \
  --soft-delete-feature-state Disable

# 保護されたアイテムの確認
az backup item list \
  --vault-name "$VAULT_NAME" --resource-group "$RG" \
  --backup-management-type AzureIaasVM -o table

# 各 VM のバックアップ停止 + データ削除
az backup protection disable \
  --vault-name "$VAULT_NAME" --resource-group "$RG" \
  --container-name "iaasvmcontainerv2;$RG;<VM名>" \
  --item-name "vm;iaasvmcontainerv2;$RG;<VM名>" \
  --delete-backup-data true --yes
```

Azure Portal の場合: Recovery Services コンテナー → **プロパティ** → 論理的な削除を OFF → **バックアップアイテム** → 各 VM の「バックアップの停止」→「バックアップデータの削除」。

### 2. AI Services モデルの削除

`enableFoundry = true` でデプロイした場合のみ必要です。

```bash
AIS_NAME="ais-<prefix>-japaneast-001"
RG="rg-spoke-<prefix>-japaneast-001"

# デプロイ済みモデル一覧
az cognitiveservices account deployment list \
  --name "$AIS_NAME" --resource-group "$RG" -o table

# 各モデルを削除
az cognitiveservices account deployment delete \
  --name "$AIS_NAME" --resource-group "$RG" \
  --deployment-name "<モデル名>" --yes
```

### 3. Automation スケジュールの削除

`enableVmAutoStartStop = true` でデプロイした場合のみ必要です。

```bash
AA_NAME="aa-<prefix>-japaneast-001"
RG="rg-spoke-<prefix>-japaneast-001"

# スケジュール一覧
az automation schedule list \
  --automation-account-name "$AA_NAME" --resource-group "$RG" -o table

# 各スケジュールを削除（start-cpuvm-001 等）
az automation schedule delete \
  --automation-account-name "$AA_NAME" --resource-group "$RG" \
  --name "<スケジュール名>" --yes
```

### 4. リソースグループの削除

ロック解除と依存リソースの処理が完了したら、リソースグループを削除します。

```bash
# Spoke → Hub の順で削除（Peering の依存方向）
az group delete --name "rg-spoke-<prefix>-japaneast-001" --yes --no-wait
az group delete --name "rg-hub-<prefix>-japaneast-001" --yes --no-wait
```

Azure Portal の場合: リソースグループ → 「リソースグループの削除」→「強制削除を適用する」にチェック → リソースグループ名を入力して削除。

### 5. VNet Flow Log の削除

postprovision で作成された VNet Flow Log はリソースグループ外に残ります。

```bash
az network watcher flow-log delete \
  --location japaneast \
  --name "flowLog-hub-<prefix>-japaneast-001"

az network watcher flow-log delete \
  --location japaneast \
  --name "flowLog-spoke-<prefix>-japaneast-001"
```

### 6. サブスクリプションレベルのデプロイ削除

```bash
# デプロイ履歴の削除
az deployment sub delete --name "deploy-hub"
az deployment sub delete --name "deploy-spoke"
az deployment sub delete --name "deploy-log-analytics"

# デプロイスタックがある場合
az stack sub delete --name "<prefix>" --action-on-unmanage detachAll --yes
```

### 7. 論理削除リソースの消去

Key Vault と AI Services は論理削除（ソフトデリート）されます。完全に消去するには以下を実行してください。

```bash
# Key Vault の消去
az keyvault purge --name "kv-<prefix>-<hash>"

# AI Services の消去（リージョンは foundryLocation に合わせる）
az cognitiveservices account purge \
  --name "ais-<prefix>-japaneast-001" \
  --resource-group "rg-spoke-<prefix>-japaneast-001" \
  --location "eastus2"
```

> AI Services のリージョンは `foundryLocation` パラメータで指定した値です（デフォルト: `eastus2`）。

## 付録: WORM 有効時のストレージ削除

`enableWorm = true` でデプロイした場合、ストレージアカウントに不変性ポリシーが設定されています。通常のリソースグループ削除ではストレージ削除が失敗する場合があります。

```bash
ST_NAME="st<prefix><hash>"
RG="rg-spoke-<prefix>-japaneast-001"

# パブリックアクセスを一時的に有効化（PE 経由でないとアクセスできないため）
az storage account update \
  --name "$ST_NAME" --resource-group "$RG" \
  --public-network-access Enabled
```

Cloud Shell（PowerShell）で不変性ポリシーを解除してから Blob を削除します。

```powershell
$StorageAccountName = "<ストレージアカウント名>"
$StorageAccountAccessKey = "<アクセスキー>"

$ctx = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccountAccessKey
$containers = Get-AzStorageContainer -Context $ctx

foreach ($container in $containers) {
  $blobs = Get-AzStorageBlob -Container $container.Name -Context $ctx -ErrorAction SilentlyContinue
  if ($blobs) {
    foreach ($blob in $blobs) {
      $blob | Remove-AzStorageBlobImmutabilityPolicy -ErrorAction SilentlyContinue
      Remove-AzStorageBlob -Blob $blob.Name -Container $container.Name -Context $ctx -ErrorAction SilentlyContinue
    }
  }
  Remove-AzStorageContainer -Name $container.Name -Context $ctx -Force -ErrorAction SilentlyContinue
}
```

> `Can not find the container` エラーは無視して問題ありません。

PowerShell 実行後、ストレージアカウントを削除します。

```bash
az storage account delete --name "$ST_NAME" --resource-group "$RG" --yes
```
