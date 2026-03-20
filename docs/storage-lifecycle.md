# ストレージアカウント ライフサイクル設定手順書   <!-- omit in toc -->

ログ収集用ストレージアカウントにライフサイクルポリシーを設定し、古いログを自動的にコスト効率のよいストレージ層に移行する手順です。

## 目次   <!-- omit in toc -->

- [前提条件](#前提条件)
- [1. ライフサイクル設定](#1-ライフサイクル設定)

## 前提条件

- Azure ロール: **共同作成者** 以上

## 1. ライフサイクル設定

### ポリシーの動作

| タイミング | アクション |
|---|---|
| 最終変更から 30 日後 | **クール層**に階層化 |
| 最終変更から 90 日後 | **アーカイブ層**に階層化 |
| 最終変更から 2,555 日後 (7 年) | **削除** |

> 日数は環境に応じて変更してください。

### Azure CLI の場合

```bash
STORAGE_ACCOUNT="<ストレージアカウント名>"
RG="<リソースグループ名>"

# アクセス追跡を有効化
az storage account blob-service-properties update \
  --account-name "$STORAGE_ACCOUNT" --resource-group "$RG" \
  --enable-last-access-tracking true

# ライフサイクルポリシーを設定
az storage account management-policy create \
  --account-name "$STORAGE_ACCOUNT" --resource-group "$RG" \
  --policy @- <<'EOF'
{
  "rules": [
    {
      "enabled": true,
      "name": "Archive-rule",
      "type": "Lifecycle",
      "definition": {
        "actions": {
          "baseBlob": {
            "tierToCool": {
              "daysAfterModificationGreaterThan": 30
            },
            "tierToArchive": {
              "daysAfterModificationGreaterThan": 90
            },
            "delete": {
              "daysAfterModificationGreaterThan": 2555
            }
          }
        },
        "filters": {
          "blobTypes": ["blockBlob"]
        }
      }
    }
  ]
}
EOF

# 設定確認
az storage account management-policy show \
  --account-name "$STORAGE_ACCOUNT" --resource-group "$RG" -o table
```

### Azure Portal の場合

１．Azure Portal にログインし、検索欄に対象ストレージアカウント名を入力して開く。

２．左ペイン → **データ管理** → **ライフサイクル管理** をクリックし、「**アクセス追跡を有効にする**」のチェックをオンにする。

３．「**コードビュー**」をクリックし、上記 JSON ルールを貼り付けて「**保存**」。
