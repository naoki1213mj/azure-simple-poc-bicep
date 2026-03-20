# SSL 証明書発行手順書   <!-- omit in toc -->

Application Gateway で使用する SSL 証明書（PFX）を発行・取得する手順です。  
用途に応じて、自己署名証明書（開発用）、Let's Encrypt（無料）、商用 CA から選択してください。

## 目次   <!-- omit in toc -->

- [証明書の種類と選び方](#証明書の種類と選び方)
- [1. 自己署名証明書の発行（開発/検証用）](#1-自己署名証明書の発行開発検証用)
- [2. Let's Encrypt 証明書の発行（無料・本番可）](#2-lets-encrypt-証明書の発行無料本番可)
- [3. 商用 CA からの証明書取得](#3-商用-ca-からの証明書取得)
- [4. Azure Key Vault で証明書を生成](#4-azure-key-vault-で証明書を生成)
- [5. PFX 形式への変換](#5-pfx-形式への変換)
- [6. 発行した証明書のデプロイ](#6-発行した証明書のデプロイ)

## 証明書の種類と選び方

| 種類 | 用途 | コスト | 有効期間 | ブラウザ警告 |
|---|---|---|---|---|
| 自己署名 | 開発・検証 | 無料 | 任意 | あり（信頼されない） |
| Let's Encrypt | 本番（DV） | 無料 | 90 日（自動更新） | なし |
| 商用 CA (DV) | 本番 | 年 $10〜 | 1 年 | なし |
| 商用 CA (OV/EV) | 本番（組織認証） | 年 $100〜 | 1 年 | なし（組織名表示） |

## 1. 自己署名証明書の発行（開発/検証用）

### OpenSSL を使用する場合

```bash
# 秘密鍵の生成
openssl genrsa -out server.key 2048

# CSR（証明書署名要求）の生成
openssl req -new -key server.key -out server.csr \
  -subj "/C=JP/ST=Tokyo/L=Chiyoda/O=Example Inc/CN=*.example.com"

# 自己署名証明書の発行（有効期間 365 日）
openssl x509 -req -days 365 \
  -in server.csr \
  -signkey server.key \
  -out server.crt \
  -extfile <(printf "subjectAltName=DNS:*.example.com,DNS:example.com")

# PFX に変換（Application Gateway で使用する形式）
openssl pkcs12 -export \
  -out server.pfx \
  -inkey server.key \
  -in server.crt \
  -passout pass:<パスワード>

# 確認
openssl pkcs12 -info -in server.pfx -passin pass:<パスワード> -nokeys
```

### ワンライナー版（最速）

```bash
# SAN 付き自己署名証明書を一発で生成して PFX に変換
openssl req -x509 -newkey rsa:2048 -sha256 -days 365 -nodes \
  -keyout server.key -out server.crt \
  -subj "/CN=*.example.com" \
  -addext "subjectAltName=DNS:*.example.com,DNS:example.com" && \
openssl pkcs12 -export -out server.pfx \
  -inkey server.key -in server.crt \
  -passout pass:<パスワード>
```

### Azure Portal の場合

Key Vault を使って自己署名証明書を直接生成することもできます（[手順 4](#4-azure-key-vault-で証明書を生成) 参照）。

## 2. Let's Encrypt 証明書の発行（無料・本番可）

### 前提条件

- 対象ドメインの DNS 管理権限があること
- [certbot](https://certbot.eff.org/) がインストール済みであること

### certbot のインストール

```bash
# macOS
brew install certbot

# Ubuntu/Debian
sudo apt-get install certbot

# RHEL/CentOS
sudo dnf install certbot
```

### DNS 認証で証明書を発行（推奨）

サーバーへの HTTP アクセスが不要な方法です。Azure DNS Zone との連携に最適。

```bash
# DNS チャレンジで証明書を発行
sudo certbot certonly \
  --manual \
  --preferred-challenges dns \
  -d "*.example.com" \
  -d "example.com" \
  --agree-tos \
  --email ops@example.com
```

certbot が TXT レコードの追加を要求するので、Azure DNS Zone に登録します:

```bash
# certbot が指示した値を Azure DNS Zone に追加
az network dns record-set txt add-record \
  --resource-group "<DNS Zone のリソースグループ>" \
  --zone-name "example.com" \
  --record-set-name "_acme-challenge" \
  --value "<certbot が表示した値>"

# DNS 伝搬を確認（TXT レコードが見えるまで待つ）
nslookup -type=TXT _acme-challenge.example.com
```

DNS 伝搬を確認できたら、certbot のプロンプトで Enter を押して発行を完了します。

### 発行された証明書を PFX に変換

```bash
# Let's Encrypt の証明書は /etc/letsencrypt/live/<domain>/ に保存される
sudo openssl pkcs12 -export \
  -out server.pfx \
  -inkey /etc/letsencrypt/live/example.com/privkey.pem \
  -in /etc/letsencrypt/live/example.com/fullchain.pem \
  -passout pass:<パスワード>
```

### 自動更新の設定

Let's Encrypt 証明書は 90 日で期限切れになるため、自動更新を設定します。

```bash
# cron で自動更新（毎月 1 日の 3:00 に実行）
echo "0 3 1 * * root certbot renew --quiet && openssl pkcs12 -export -out /path/to/server.pfx -inkey /etc/letsencrypt/live/example.com/privkey.pem -in /etc/letsencrypt/live/example.com/fullchain.pem -passout pass:<パスワード>" | sudo tee /etc/cron.d/certbot-renew
```

> **Tips**: 更新後の Key Vault へのアップロードは [SSL 証明書更新手順書](ssl-certificate-renewal.md) を参照してください。

## 3. 商用 CA からの証明書取得

### 3-1. CSR の生成

```bash
# 秘密鍵の生成
openssl genrsa -out server.key 2048

# CSR の生成（CA に提出する情報）
openssl req -new -key server.key -out server.csr \
  -subj "/C=JP/ST=Tokyo/L=Chiyoda/O=<組織名>/CN=*.example.com"

# CSR の内容を確認
openssl req -text -noout -verify -in server.csr
```

### 3-2. CA への申請

生成した `server.csr` の内容を CA（DigiCert, GlobalSign, Sectigo 等）の申請フォームに貼り付けます。

```bash
# CSR の内容を表示（これを CA に提出）
cat server.csr
```

### 3-3. 証明書の受領と PFX 変換

CA から証明書（`.crt` / `.cer`）と中間証明書が届いたら:

```bash
# フルチェーン証明書を作成（サーバー証明書 + 中間証明書）
cat server.crt intermediate.crt > fullchain.crt

# PFX に変換
openssl pkcs12 -export \
  -out server.pfx \
  -inkey server.key \
  -in fullchain.crt \
  -passout pass:<パスワード>
```

## 4. Azure Key Vault で証明書を生成

Key Vault の証明書生成機能を使うと、秘密鍵が Key Vault 外に出ることがなく最も安全です。

### Azure CLI の場合

```bash
KV_NAME="kv-spoke-<prefix>-jpeast"

# Key Vault で自己署名証明書を生成
az keyvault certificate create \
  --vault-name "$KV_NAME" \
  --name "sslcertkey" \
  --policy @- <<'EOF'
{
  "issuerParameters": { "name": "Self" },
  "keyProperties": {
    "exportable": true,
    "keyType": "RSA",
    "keySize": 2048,
    "reuseKey": false
  },
  "x509CertificateProperties": {
    "subject": "CN=*.example.com",
    "subjectAlternativeNames": {
      "dnsNames": ["*.example.com", "example.com"]
    },
    "validityInMonths": 12
  }
}
EOF

# 生成結果を確認
az keyvault certificate show \
  --vault-name "$KV_NAME" \
  --name "sslcertkey" \
  --query "{name:name, notBefore:attributes.notBefore, expires:attributes.expires}" \
  -o table
```

### Azure Portal の場合

１．Azure Portal で `kv-spoke-<prefix>-jpeast` を開く。

２．左ペイン → **証明書** → 「**+ 生成/インポート**」をクリック。

３．以下を入力:

| 設定項目 | 設定値 |
|---|---|
| 証明書の作成方法 | 生成 |
| 証明書の名前 | `sslcertkey` |
| 証明機関 (CA) の種類 | 自己署名済み証明書 |
| サブジェクト | `CN=*.example.com` |
| DNS 名 | `*.example.com`, `example.com` |
| 有効期間（月） | 12 |
| コンテンツの種類 | PKCS #12 |

４．「**作成**」をクリック。

### Key Vault から PFX をダウンロード（外部利用が必要な場合）

```bash
# シークレットとして PFX をダウンロード
az keyvault secret download \
  --vault-name "$KV_NAME" \
  --name "sslcertkey" \
  --file server.pfx \
  --encoding base64
```

## 5. PFX 形式への変換

他の形式から PFX に変換するコマンド集です。

```bash
# PEM (秘密鍵 + 証明書) → PFX
openssl pkcs12 -export \
  -out server.pfx \
  -inkey privkey.pem \
  -in fullchain.pem \
  -passout pass:<パスワード>

# DER (.cer) → PEM → PFX
openssl x509 -inform DER -in server.cer -out server.crt
openssl pkcs12 -export \
  -out server.pfx \
  -inkey server.key \
  -in server.crt \
  -passout pass:<パスワード>

# 既存 PFX のパスワード変更
openssl pkcs12 -in old.pfx -nodes -passin pass:<旧パスワード> | \
openssl pkcs12 -export -out new.pfx -passout pass:<新パスワード>

# PFX の内容確認
openssl pkcs12 -info -in server.pfx -passin pass:<パスワード> -nokeys
```

## 6. 発行した証明書のデプロイ

### azd でのデプロイ時

```bash
# PFX を所定の場所に配置
mkdir -p infra/certs
cp server.pfx infra/certs/server.pfx

# パスワードを環境変数に設定
azd env set SSL_PASSWORD "<パスワード>"

# デプロイ
azd up
```

### 手動で Key Vault にインポート

```bash
az keyvault certificate import \
  --vault-name "kv-spoke-<prefix>-jpeast" \
  --name "sslcertkey" \
  --file server.pfx \
  --password "<パスワード>"
```

> 証明書の更新手順は [SSL 証明書更新手順書](ssl-certificate-renewal.md) を参照してください。
