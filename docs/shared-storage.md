# 共有ストレージ作成手順書   <!-- omit in toc -->

複数の VM に NFS 共有ストレージをマウントする手順です。Azure Files (Premium / NFS) を使用します。

## 目次   <!-- omit in toc -->

- [前提条件](#前提条件)
- [1. ストレージアカウント作成](#1-ストレージアカウント作成)
- [2. ファイル共有の作成](#2-ファイル共有の作成)
- [3. VM へのマウント設定](#3-vm-へのマウント設定)

## 前提条件

- Azure ロール: **共同作成者** 以上
- VM が VNet 内のサブネットに接続されていること

## 1. ストレージアカウント作成

### Azure CLI の場合

```bash
PREFIX="<prefix>"
RG="rg-spoke-${PREFIX}-japaneast-001"
VNET="vnet-spoke-${PREFIX}-japaneast-001"
SUBNET="snet-vm-${PREFIX}-001"

# Premium FileStorage アカウントを作成
az storage account create \
  --name "stfs${PREFIX}001" \
  --resource-group "$RG" \
  --location japaneast \
  --sku Premium_LRS \
  --kind FileStorage \
  --enable-nfs-v3 true \
  --default-action Deny \
  --bypass AzureServices

# VNet サービスエンドポイントを追加
az network vnet subnet update \
  --resource-group "$RG" \
  --vnet-name "$VNET" \
  --name "$SUBNET" \
  --service-endpoints Microsoft.Storage

# ネットワークルールを追加
SUBNET_ID=$(az network vnet subnet show \
  --resource-group "$RG" --vnet-name "$VNET" --name "$SUBNET" \
  --query id -o tsv)

az storage account network-rule add \
  --account-name "stfs${PREFIX}001" \
  --resource-group "$RG" \
  --subnet "$SUBNET_ID"
```

### Azure Portal の場合

１．Azure Portal → **ストレージアカウント** → 「**＋ 作成**」をクリック。

２．以下を入力:

| 設定項目 | 設定値 |
|---|---|
| リソースグループ | `rg-spoke-<prefix>-japaneast-001` |
| ストレージアカウント名 | `stfs<prefix>001` |
| リージョン | Japan East |
| パフォーマンス | **Premium** |
| Premium アカウントの種類 | **ファイル共有** |
| 冗長性 | LRS |

３．**ネットワーク** 画面で:

| 設定項目 | 設定値 |
|---|---|
| ネットワークアクセス | 選択した仮想ネットワークと IP アドレスからのパブリックアクセスを有効にする |
| 仮想ネットワーク | `vnet-spoke-<prefix>-japaneast-001` |
| サブネット | `snet-vm-<prefix>-001` |

## 2. ファイル共有の作成

### Azure CLI の場合

```bash
# NFS ファイル共有を作成
az storage share-rm create \
  --storage-account "stfs${PREFIX}001" \
  --resource-group "$RG" \
  --name "shared-data" \
  --quota 4096 \
  --enabled-protocols NFS \
  --root-squash NoRootSquash
```

### Azure Portal の場合

１．ストレージアカウント → 左ペイン → **データストレージ** → **ファイル共有** → 「**＋ ファイル共有**」。

２．以下を入力:

| 設定項目 | 設定値 |
|---|---|
| 名前 | `shared-data` |
| プロビジョニング済みストレージ (GiB) | 4096 |
| プロトコル | **NFS** |
| ルートスカッシュ | ルートスカッシュなし |

## 3. VM へのマウント設定

Bastion 経由で VM に接続し、以下を実行します。

```bash
# Bastion トンネル経由で SSH 接続
az network bastion tunnel \
  --name "bas-<prefix>-japaneast-001" \
  --resource-group "rg-hub-<prefix>-japaneast-001" \
  --target-resource-id "<VM リソース ID>" \
  --resource-port 22 --port 50026

# 別ターミナルで:
ssh -p 50026 -i "<秘密鍵パス>" azureuser@127.0.0.1
```

VM に接続後:

```bash
# NFS ユーティリティのインストール
sudo dnf install -y nfs-utils

# マウントポイント作成
sudo mkdir -p /datadrive

# 手動マウント
sudo mount -t nfs \
  stfs<prefix>001.file.core.windows.net:/stfs<prefix>001/shared-data \
  /datadrive \
  -o vers=4,minorversion=1,sec=sys,nconnect=4

# 自動マウント設定 (/etc/fstab に追記)
echo "stfs<prefix>001.file.core.windows.net:/stfs<prefix>001/shared-data /datadrive nfs vers=4,minorversion=1,_netdev,nofail,sec=sys 0 0" | sudo tee -a /etc/fstab

# 再起動して自動マウントを確認
sudo reboot
```

再起動後に再接続し、マウントを確認:

```bash
df -Th | grep datadrive
```

期待される出力:
```
stfs<prefix>001.file.core.windows.net:/stfs<prefix>001/shared-data  nfs4  4.0T  0  4.0T  0% /datadrive
```
