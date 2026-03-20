# 環境削除手順書   <!-- omit in toc -->

Hub-Spoke PoC 環境を安全に削除する手順です。リソース間の依存関係があるため、以下の順序で削除してください。

## 目次   <!-- omit in toc -->

- [前提条件](#前提条件)
- [azd を使った削除（推奨）](#azd-を使った削除推奨)
- [手動削除](#手動削除)
  - [1. Recovery Services コンテナー削除](#1-recovery-services-コンテナー削除)
  - [2. AI Foundry モデル削除](#2-ai-foundry-モデル削除)
  - [3. Automation アカウントの jobSchedule 設定削除](#3-automation-アカウントの-jobschedule-設定削除)
  - [4. Spoke リソースグループの削除](#4-spoke-リソースグループの削除)
  - [5. Hub リソースグループの削除](#5-hub-リソースグループの削除)
  - [6. NSG フローログの削除](#6-nsg-フローログの削除)
  - [7. デプロイおよびデプロイスタックの削除](#7-デプロイおよびデプロイスタックの削除)
  - [8. 論理削除リソースの削除](#8-論理削除リソースの削除)
    - [Key Vault の消去](#key-vault-の消去)
    - [AI Services リソースの消去](#ai-services-リソースの消去)
- [付録: ストレージアカウント WORM 有効時の削除](#付録-ストレージアカウント-worm-有効時の削除)

## 前提条件

- サブスクリプションに **所有者 (Owner)** ロールが付与されていること

## azd を使った削除（推奨）

```bash
azd down
```

> **注意**: `azd down` ではリソースロック付きリソースや論理削除リソースの消去は行われません。
> 以下の手動手順で残りのリソースを確認・削除してください。

## 手動削除

### 1. Recovery Services コンテナー削除

バックアップが有効な場合、リソースグループ削除前に Recovery Services コンテナーの保護を停止する必要があります。

#### Azure Portal の場合

１．Azure Portal で「Recovery Services コンテナー」を検索し、`bvault-spoke-<prefix>-jpeast-001` を開く。

２．左ペイン → **設定** → **プロパティ** → 「論理的な削除とセキュリティの設定」の「更新」をクリック。

３．以下の設定に変更し「更新」をクリック:

| 設定項目 | 設定値 |
|---|---|
| クラウド ワークロードの論理的な削除を有効にする | OFF |
| ハイブリッド ワークロードの論理的な削除とセキュリティ設定を有効にする | OFF |

４．左ペイン → **保護されたアイテム** → **バックアップアイテム** → 「Azure Virtual Machine」を開く。

５．各 VM の「…」→「**バックアップの停止**」をクリックし、「**バックアップデータの削除**」を選択して停止。

６．すべてのバックアップ項目の数が「0」になることを確認。

#### Azure CLI の場合

```bash
VAULT_NAME="bvault-spoke-<prefix>-jpeast-001"
RG="rg-spoke-<prefix>-jpeast-001"

# 論理的な削除を無効化
az backup vault backup-properties set \
  --name "$VAULT_NAME" --resource-group "$RG" \
  --soft-delete-feature-state Disable

# 保護されたアイテムの一覧取得
az backup item list \
  --vault-name "$VAULT_NAME" --resource-group "$RG" \
  --backup-management-type AzureIaasVM -o table

# 各VMのバックアップ停止+データ削除
az backup protection disable \
  --vault-name "$VAULT_NAME" --resource-group "$RG" \
  --container-name "iaasvmcontainerv2;$RG;<VM名>" \
  --item-name "vm;iaasvmcontainerv2;$RG;<VM名>" \
  --delete-backup-data true --yes
```

### 2. AI Foundry モデル削除

#### Azure Portal の場合

１．Azure Portal で `ais-foundry-spoke-<prefix>-jpeast-001` を検索して開く。

２．「**Go to Azure AI Foundry portal**」をクリック。

３．左ペイン → **deployment** → 各モデルをチェックして「**削除**」をクリック。

４．すべてのモデルが表示されなくなることを確認。

#### Azure CLI の場合

```bash
AIS_NAME="ais-foundry-spoke-<prefix>-jpeast-001"
RG="rg-spoke-<prefix>-jpeast-001"

# デプロイ済みモデルの一覧
az cognitiveservices account deployment list \
  --name "$AIS_NAME" --resource-group "$RG" -o table

# 各モデルを削除
az cognitiveservices account deployment delete \
  --name "$AIS_NAME" --resource-group "$RG" \
  --deployment-name "<モデル名>" --yes
```

### 3. Automation アカウントの jobSchedule 設定削除

#### Azure Portal の場合

１．Azure Portal で `am-spoke-<prefix>-jpeast-001` を検索して開く。

２．左ペイン → **共有リソース** → **スケジュール** を開く。

３．各スケジュール（`am-rbsc-cpuvm-spoke-*` / `am-rbsc-gpuvm-spoke-*`）を選択して「**削除**」。

#### Azure CLI の場合

```bash
AA_NAME="am-spoke-<prefix>-jpeast-001"
RG="rg-spoke-<prefix>-jpeast-001"

# スケジュール一覧
az automation schedule list \
  --automation-account-name "$AA_NAME" --resource-group "$RG" -o table

# 各スケジュールを削除
az automation schedule delete \
  --automation-account-name "$AA_NAME" --resource-group "$RG" \
  --name "<スケジュール名>" --yes
```

### 4. Spoke リソースグループの削除

#### Azure Portal の場合

１．リソースグループ `rg-spoke-<prefix>-jpeast-001` を開く。

２．「**リソースグループの削除**」をクリック。

３．「選択した仮想マシンと仮想マシンスケールセットに対して強制削除を適用する」にチェックを入れ、リソースグループ名を入力して「**削除**」。

#### Azure CLI の場合

```bash
az group delete --name "rg-spoke-<prefix>-jpeast-001" --yes --no-wait
```

### 5. Hub リソースグループの削除

`rg-hub-<prefix>-jpeast-001` に対して、手順 4 と同様に削除を実行。

```bash
az group delete --name "rg-hub-<prefix>-jpeast-001" --yes --no-wait
```

### 6. NSG フローログの削除

#### Azure Portal の場合

１．Azure Portal で「**Network Watcher**」を検索して開く。

２．左ペイン → **フローログ** → `<prefix>` で始まるものをすべてチェックして「**削除**」。

#### Azure CLI の場合

```bash
# フローログの一覧
az network watcher flow-log list --location japaneast -o table

# 各フローログを削除
az network watcher flow-log delete \
  --location japaneast \
  --name "flowLog-hub-<prefix>-jpeast-001"

az network watcher flow-log delete \
  --location japaneast \
  --name "flowLog-spoke-<prefix>-jpeast-001"
```

### 7. デプロイおよびデプロイスタックの削除

#### Azure Portal の場合

１．Azure Portal → **サブスクリプション** → 対象サブスクリプション → 左ペイン **デプロイ**。

２．`<prefix>` で始まるデプロイにチェックを入れ「**削除**」。

３．左ペイン → **デプロイスタック** → `<prefix>` にチェック → 「**スタックの削除**」。

４．「リソースとリソースグループをデタッチする」を選択して削除。

#### Azure CLI の場合

```bash
# デプロイの削除
az deployment sub delete --name "<prefix>"

# デプロイスタックの削除（リソースをデタッチ）
az stack sub delete \
  --name "<prefix>" \
  --action-on-unmanage detachAll --yes
```

### 8. 論理削除リソースの削除

#### Key Vault の消去

```bash
az keyvault purge --name "kv-spoke-<prefix>-jpeast"
```

または、Azure Portal で:
１．**キーコンテナー** → 「**削除されたコンテナーの管理**」→ 対象を選択して「**消去**」。

#### AI Services リソースの消去

```bash
az cognitiveservices account purge \
  --name "ais-foundry-spoke-<prefix>-jpeast-001" \
  --resource-group "rg-spoke-<prefix>-jpeast-001" \
  --location "<location>"
```

## 付録: ストレージアカウント WORM 有効時の削除

WORM（不変性ポリシー）が有効なストレージアカウントを削除するには、追加手順が必要です。

１．Azure Portal で `stspoke<prefix>jpeast` を開く。

２．左ペイン → **データ管理** → **データ保護** → 「**ポリシーの管理**」→ 時間ベースの保持を「**削除**」。

３．左ペイン → **セキュリティとネットワーク** → **ネットワーク** → **Public network access** を「**Enable**」に変更して「**Save**」。

> **CLI でのネットワーク公開設定変更:**
> ```bash
> az storage account update \
>   --name "stspoke<prefix>jpeast" \
>   --resource-group "rg-spoke-<prefix>-jpeast-001" \
>   --public-network-access Enabled
> ```

４．Cloud Shell（PowerShell）で以下のスクリプトを実行:

```powershell
$StorageAccountName = "<ストレージアカウント名>"
$StorageAccountAccessKey = "<アクセスキー>"

# 全コンテナーの不変性ポリシーを解除してBlob削除
$containers = @(
  "am-azkvauditlogs"
  "insights-logs-flowlogflowevent"
  "am-heartbeat"
  "am-perf"
  "am-syslog"
  "am-azureactivity"
  "am-usage"
)

foreach ($containerName in $containers) {
  $ctx = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccountAccessKey
  $blobs = Get-AzStorageBlob -Container $containerName -Context $ctx -ErrorAction SilentlyContinue
  if ($blobs) {
    foreach ($blob in $blobs) {
      $blob | Remove-AzStorageBlobImmutabilityPolicy -ErrorAction SilentlyContinue
      Remove-AzStorageBlob -Blob $blob.Name -Container $containerName -Context $ctx -ErrorAction SilentlyContinue
    }
  }
}
```

> **注意**: `Can not find the container` エラーが表示されても問題ありません。環境によっては存在しないコンテナーがあります。

５．コンテナーとストレージアカウントを削除する。

```bash
# コンテナーの一覧確認
az storage container list \
  --account-name "stspoke<prefix>jpeast" \
  --account-key "<アクセスキー>" -o table

# コンテナー削除
az storage container delete \
  --name "<コンテナー名>" \
  --account-name "stspoke<prefix>jpeast" \
  --account-key "<アクセスキー>"

# ストレージアカウント削除
az storage account delete \
  --name "stspoke<prefix>jpeast" \
  --resource-group "rg-spoke-<prefix>-jpeast-001" --yes
```

または Azure Portal で左ペイン → **データストレージ** → **コンテナー** から手動削除し、概要画面から「**削除**」。
