# SSL 証明書更新手順書   <!-- omit in toc -->

Application Gateway で使用する SSL 証明書（PFX）を Key Vault 経由で更新する手順です。

## 目次   <!-- omit in toc -->

- [前提条件](#前提条件)
- [1. 新しい SSL 証明書の準備](#1-新しい-ssl-証明書の準備)
- [2. Key Vault への証明書インポート](#2-key-vault-への証明書インポート)
- [3. Application Gateway の証明書更新](#3-application-gateway-の証明書更新)
- [4. 更新後の動作確認](#4-更新後の動作確認)

## 前提条件

- Azure サブスクリプションの**所有者**ロールが付与されていること
- Azure CLI がインストール済みであること
- 新しい SSL 証明書（PFX 形式）とそのパスワードが準備されていること

## 1. 新しい SSL 証明書の準備

新しい PFX 証明書ファイルを準備します。

> **Tips**: Let's Encrypt 等の PEM 証明書を PFX に変換する場合:
> ```bash
> openssl pkcs12 -export \
>   -out server.pfx \
>   -inkey privkey.pem \
>   -in fullchain.pem \
>   -passout pass:<password>
> ```

## 2. Key Vault への証明書インポート

### Azure CLI を使用する場合

```bash
# Key Vault に新しい証明書をインポート
az keyvault certificate import \
  --vault-name "kv-<prefix>-<hash>" \
  --name "sslcertkey" \
  --file "<新しい証明書のパス>.pfx" \
  --password "<証明書のパスワード>"

# インポート結果を確認
az keyvault certificate show \
  --vault-name "kv-<prefix>-<hash>" \
  --name "sslcertkey" \
  --query "{name:name, notBefore:attributes.notBefore, expires:attributes.expires}" \
  -o table
```

### Azure Portal を使用する場合

１．Azure Portal で `kv-<prefix>-<hash>` を検索して開く。

２．左ペインの「**証明書**」をクリックする。

３．`sslcertkey` をクリックし、「**新しいバージョン**」をクリックする。

４．「**証明書のインポート方法**」で「インポート」を選択し、PFX ファイルとパスワードを入力して「**作成**」をクリックする。

## 3. Application Gateway の証明書更新

Application Gateway は Key Vault の `/secrets/sslcertkey` を参照しているため、Key Vault の証明書を更新すると自動的に反映されます。

> **注意**: 自動反映には最大 4 時間かかる場合があります。即時反映が必要な場合は以下を実行してください。

```bash
# Application Gateway を強制的に更新
az network application-gateway stop \
  --resource-group "rg-hub-<prefix>-japaneast-001" \
  --name "appgw-hub-<prefix>-japaneast-001"

az network application-gateway start \
  --resource-group "rg-hub-<prefix>-japaneast-001" \
  --name "appgw-hub-<prefix>-japaneast-001"
```

## 4. 更新後の動作確認

### ブラウザ確認

１．ブラウザで `https://<prefix><randid>.<domain>` にアクセスする。

２．SSL 証明書の有効期限が新しい日付に更新されていることを確認する。

### CLI 確認

```bash
# SSL 証明書の有効期限を確認
echo | openssl s_client -connect <prefix><randid>.<domain>:443 -servername <prefix><randid>.<domain> 2>/dev/null | openssl x509 -noout -dates
```

出力例:
```
notBefore=Mar 20 00:00:00 2026 GMT
notAfter=Mar 20 23:59:59 2027 GMT
```
