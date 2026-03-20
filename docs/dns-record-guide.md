# DNS レコード登録手順書   <!-- omit in toc -->

Application Gateway で外部公開する際に、カスタムドメインの DNS レコードを Azure DNS Zone に登録する手順です。

## 目次   <!-- omit in toc -->

- [前提条件](#前提条件)
- [1. Azure テナントの確認](#1-azure-テナントの確認)
- [2. DNS ゾーンでレコードセットを追加](#2-dns-ゾーンでレコードセットを追加)

## 前提条件

- Azure DNS Zone が作成済みであり、対象ドメインの管理権限があること
- Application Gateway のパブリック IP アドレスが取得済みであること

## 1. Azure テナントの確認

１．Azure Portal にサインインし、右上のアイコンから **ディレクトリの切り替え** を開く。

２．一覧の中から、DNS Zone が存在するテナントが「現在」となっていることを確認する。

- 「現在」でない場合は「切り替え」をクリックしてテナントを切り替える。

## 2. DNS ゾーンでレコードセットを追加

### Azure Portal の場合

１．Azure Portal の検索欄に対象ドメイン名（例: `example.com`）を入力し、該当する DNS ゾーンを開く。

２．上部メニューの「**+ レコードセット**」をクリックする。

３．以下の値を入力し、「**OK**」をクリックする。

| 設定項目 | 設定値 | 備考 |
|---|---|---|
| 名前 | `<prefix><randid>` | 例: `myenv01abc12345` |
| 種類 | A | |
| エイリアスレコードセット | いいえ | |
| TTL | 1 | |
| TTL の単位 | 時間 | |
| IP アドレス | `<Application Gateway のパブリック IP>` | |

### Azure CLI の場合

```bash
# Application Gateway のパブリック IP を取得
AGW_IP=$(az network public-ip show \
  --resource-group "rg-hub-<prefix>-jpeast-001" \
  --name "pip-appgw-hub-<prefix>-jpeast-001" \
  --query ipAddress -o tsv)

echo "Application Gateway IP: $AGW_IP"

# A レコードを追加
az network dns record-set a add-record \
  --resource-group "<DNS Zone のリソースグループ>" \
  --zone-name "<ドメイン名>" \
  --record-set-name "<prefix><randid>" \
  --ipv4-address "$AGW_IP" \
  --ttl 3600

# 登録確認
az network dns record-set a show \
  --resource-group "<DNS Zone のリソースグループ>" \
  --zone-name "<ドメイン名>" \
  --name "<prefix><randid>" -o table
```

４．追加後、レコードセットの一覧に新しい A レコードが表示されることを確認する。

５．名前解決と接続を確認する。

```bash
# DNS 解決確認
nslookup <prefix><randid>.<domain>

# HTTPS 接続確認
curl -I "https://<prefix><randid>.<domain>"
```
