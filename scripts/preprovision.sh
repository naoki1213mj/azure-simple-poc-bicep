#!/usr/bin/env bash
# =============================================================================
# preprovision.sh - azd provision 前の事前処理
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="${SCRIPT_DIR}/../infra"
KEYS_DIR="${INFRA_DIR}/keys"
CERTS_DIR="${INFRA_DIR}/certs"

echo "=== preprovision: 事前処理を開始します ==="

# -----------------------------------------------
# 1. SSH 鍵の生成（存在しない場合のみ）
# -----------------------------------------------
mkdir -p "${KEYS_DIR}"
if [ ! -f "${KEYS_DIR}/id_rsa" ]; then
  echo "SSH 鍵ペアを生成しています..."
  ssh-keygen -t rsa -b 4096 -N "" -f "${KEYS_DIR}/id_rsa" -q
  echo "SSH 鍵ペアを生成しました: ${KEYS_DIR}/id_rsa"
else
  echo "SSH 鍵ペアは既に存在します: ${KEYS_DIR}/id_rsa"
fi

# -----------------------------------------------
# 2. 乱数 ID の生成（環境変数にセット）
# -----------------------------------------------
if [ -z "${RAND_ID:-}" ]; then
  RAND_ID=$(cat /dev/urandom | LC_ALL=C tr -dc 'a-z0-9' | head -c 8)
  echo "乱数 ID を生成しました: ${RAND_ID}"
  azd env set RAND_ID "${RAND_ID}"
fi

# -----------------------------------------------
# 3. prefix の確認
# -----------------------------------------------
if [ -z "${AZURE_PREFIX:-}" ]; then
  echo "エラー: AZURE_PREFIX が設定されていません。"
  echo "  azd env set AZURE_PREFIX <your-prefix>"
  echo "  (英小文字/数字 3-7 桁)"
  exit 1
fi

# prefix の長さと文字種チェック
if ! echo "${AZURE_PREFIX}" | grep -qE '^[a-z0-9]{3,7}$'; then
  echo "エラー: AZURE_PREFIX は英小文字と数字のみ、3-7 文字で指定してください。"
  echo "  現在の値: ${AZURE_PREFIX}"
  exit 1
fi

# -----------------------------------------------
# 4. Azure ログインの確認
# -----------------------------------------------
echo "Azure ログイン状態を確認しています..."
if ! az account show > /dev/null 2>&1; then
  echo "Azure にログインしてください: az login"
  exit 1
fi

SUBSCRIPTION_ID=$(az account show --query id -o tsv)
echo "サブスクリプション: ${SUBSCRIPTION_ID}"

# -----------------------------------------------
# 5. principalid の取得
# -----------------------------------------------
if [ -z "${AZURE_PRINCIPAL_ID:-}" ]; then
  CURRENT_UPN=$(az ad signed-in-user show --query userPrincipalName -o tsv 2>/dev/null || echo "")
  if [ -n "${CURRENT_UPN}" ]; then
    PRINCIPAL_ID=$(az ad signed-in-user show --query id -o tsv)
    echo "プリンシパル ID を取得しました: ${PRINCIPAL_ID}"
    azd env set AZURE_PRINCIPAL_ID "${PRINCIPAL_ID}"
  else
    echo "警告: プリンシパル ID を自動取得できませんでした。手動で設定してください:"
    echo "  azd env set AZURE_PRINCIPAL_ID <object-id>"
  fi
fi

# -----------------------------------------------
# 6. リソースプロバイダー登録
# -----------------------------------------------
echo "リソースプロバイダーを確認・登録しています..."
PROVIDERS=(
  "Microsoft.ADHybridHealthService"
  "Microsoft.Advisor"
  "Microsoft.AlertsManagement"
  "Microsoft.Authorization"
  "Microsoft.Automation"
  "Microsoft.Billing"
  "Microsoft.Capacity"
  "Microsoft.ChangeAnalysis"
  "Microsoft.ClassicSubscription"
  "Microsoft.CognitiveServices"
  "Microsoft.Commerce"
  "Microsoft.Compute"
  "Microsoft.Consumption"
  "Microsoft.CostManagement"
  "Microsoft.DevTestLab"
  "Microsoft.Features"
  "Microsoft.ManagedIdentity"
  "Microsoft.MarketplaceOrdering"
  "Microsoft.Network"
  "Microsoft.OperationalInsights"
  "Microsoft.Portal"
  "Microsoft.RecoveryServices"
  "Microsoft.ResourceGraph"
  "Microsoft.ResourceHealth"
  "Microsoft.ResourceNotifications"
  "Microsoft.Resources"
  "Microsoft.SerialConsole"
  "Microsoft.Storage"
  "Microsoft.Insights"
  "microsoft.support"
)

for provider in "${PROVIDERS[@]}"; do
  status=$(az provider show -n "${provider}" --query "registrationState" -o tsv 2>/dev/null || echo "NotRegistered")
  if [ "${status}" != "Registered" ]; then
    echo "  登録中: ${provider}"
    az provider register --namespace "${provider}" --wait > /dev/null 2>&1 || true
  fi
done
echo "リソースプロバイダーの確認が完了しました。"

# -----------------------------------------------
# 7. 論理削除リソースの復元（再デプロイ時の名前衝突回避）
# -----------------------------------------------
LOCATION="${AZURE_LOCATION:-japaneast}"
SPOKE_RG="rg-spoke-${AZURE_PREFIX}-${LOCATION}-001"

echo "論理削除された Key Vault を確認しています..."
DELETED_KVS=$(az keyvault list-deleted --query "[?contains(name,'${AZURE_PREFIX}')].name" -o tsv 2>/dev/null || echo "")
if [ -n "${DELETED_KVS}" ]; then
  for kv_name in ${DELETED_KVS}; do
    echo "  論理削除された Key Vault を復元中: ${kv_name}"
    az keyvault recover --name "${kv_name}" --only-show-errors 2>/dev/null || echo "  復元をスキップしました（既に存在する可能性があります）"
  done
fi

echo "論理削除された AI Services を確認しています..."
DELETED_AIS=$(az cognitiveservices account list-deleted --query "[?contains(name,'${AZURE_PREFIX}')].{name:name, rg:resourceGroup, location:location}" -o tsv 2>/dev/null || echo "")
if [ -n "${DELETED_AIS}" ]; then
  echo "${DELETED_AIS}" | while IFS=$'\t' read -r ais_name ais_rg ais_location; do
    echo "  論理削除された AI Services を復元中: ${ais_name}"
    az cognitiveservices account recover --name "${ais_name}" --resource-group "${ais_rg}" --location "${ais_location}" --only-show-errors 2>/dev/null || echo "  復元をスキップしました"
  done
fi

# -----------------------------------------------
# 8. SSL 証明書の確認（AGW有効時）
# -----------------------------------------------
ENABLE_APP_GATEWAY="${ENABLE_APP_GATEWAY:-false}"
if [ "${ENABLE_APP_GATEWAY}" = "true" ]; then
  mkdir -p "${CERTS_DIR}"
  SSL_CERT_FILE="${SSL_CERT_FILE:-certs/server.pfx}"
  CERT_PATH="${INFRA_DIR}/${SSL_CERT_FILE}"
  if [ ! -f "${CERT_PATH}" ]; then
    echo ""
    echo "警告: SSL 証明書が見つかりません: ${CERT_PATH}"
    echo "  Application Gateway を使用する場合は、PFX 形式の SSL 証明書を配置してください。"
    echo "  配置先: ${CERT_PATH}"
    echo "  または: azd env set SSL_CERT_FILE <path-to-pfx>"
    echo ""
  fi
fi

echo "=== preprovision: 事前処理が完了しました ==="
