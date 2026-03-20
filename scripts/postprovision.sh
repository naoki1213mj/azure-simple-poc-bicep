#!/usr/bin/env bash
# =============================================================================
# postprovision.sh - azd provision 後の後処理
# =============================================================================
set -euo pipefail

echo "=== postprovision: 後処理を開始します ==="

PREFIX="${AZURE_PREFIX:-}"
LOCATION="${AZURE_LOCATION:-japaneast}"
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

if [ -z "${PREFIX}" ]; then
  echo "エラー: AZURE_PREFIX が設定されていません。"
  exit 1
fi

# -----------------------------------------------
# 1. VNet Flow Log の作成
# -----------------------------------------------
echo "VNet Flow Log を作成しています..."

HUB_RG="rg-hub-${PREFIX}-${LOCATION}-001"
SPOKE_RG="rg-spoke-${PREFIX}-${LOCATION}-001"
HUB_VNET="vnet-hub-${PREFIX}-${LOCATION}-001"
SPOKE_VNET="vnet-spoke-${PREFIX}-${LOCATION}-001"

# ストレージアカウント名を動的に取得（AVM が uniqueString を使うため）
STORAGE_ACCOUNT=$(az storage account list --resource-group "${SPOKE_RG}" --query "[0].name" -o tsv 2>/dev/null || echo "")
LOG_WORKSPACE=$(az monitor log-analytics workspace list --resource-group "${SPOKE_RG}" --query "[0].name" -o tsv 2>/dev/null || echo "")

STORAGE_ID="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${SPOKE_RG}/providers/Microsoft.Storage/storageAccounts/${STORAGE_ACCOUNT}"
WORKSPACE_ID="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${SPOKE_RG}/providers/Microsoft.OperationalInsights/workspaces/${LOG_WORKSPACE}"

if [ -z "${STORAGE_ACCOUNT}" ] || [ -z "${LOG_WORKSPACE}" ]; then
  echo "警告: ストレージアカウントまたは Log Analytics が見つかりません。VNet Flow Log の作成をスキップします。"
else

# Hub VNet Flow Log
az network watcher flow-log create \
  --location "${LOCATION}" \
  --name "flowLog-hub-${PREFIX}-${LOCATION}-001" \
  --resource-group "${HUB_RG}" \
  --vnet "${HUB_VNET}" \
  --storage-account "${STORAGE_ID}" \
  --workspace "${WORKSPACE_ID}" \
  --interval 10 \
  --traffic-analytics true \
  --only-show-errors 2>/dev/null || echo "Hub VNet Flow Log の作成をスキップしました（既存の可能性があります）"

# Spoke VNet Flow Log
az network watcher flow-log create \
  --location "${LOCATION}" \
  --name "flowLog-spoke-${PREFIX}-${LOCATION}-001" \
  --resource-group "${SPOKE_RG}" \
  --vnet "${SPOKE_VNET}" \
  --storage-account "${STORAGE_ACCOUNT}" \
  --workspace "${LOG_WORKSPACE}" \
  --interval 10 \
  --traffic-analytics true \
  --only-show-errors 2>/dev/null || echo "Spoke VNet Flow Log の作成をスキップしました（既存の可能性があります）"

echo "VNet Flow Log の作成が完了しました。"

fi  # storage/workspace check

# -----------------------------------------------
# 2. SSL 証明書の Key Vault 登録（AGW有効時）
# -----------------------------------------------
ENABLE_APP_GATEWAY="${ENABLE_APP_GATEWAY:-false}"
if [ "${ENABLE_APP_GATEWAY}" = "true" ]; then
  KV_NAME=$(az keyvault list --resource-group "${SPOKE_RG}" --query "[0].name" -o tsv 2>/dev/null || echo "")
  SSL_CERT_FILE="${SSL_CERT_FILE:-certs/server.pfx}"
  SSL_PASSWORD="${SSL_PASSWORD:-}"
  CERT_PATH="infra/${SSL_CERT_FILE}"

  if [ -f "${CERT_PATH}" ]; then
    echo "SSL 証明書を Key Vault に登録しています..."
    PRINCIPAL_ID="${AZURE_PRINCIPAL_ID:-}"
    if [ -n "${PRINCIPAL_ID}" ]; then
      az keyvault set-policy \
        --name "${KV_NAME}" \
        --resource-group "${SPOKE_RG}" \
        --object-id "${PRINCIPAL_ID}" \
        --secret-permissions all \
        --certificate-permissions all \
        --key-permissions all \
        --only-show-errors 2>/dev/null || true
    fi

    az keyvault certificate import \
      --vault-name "${KV_NAME}" \
      --file "${CERT_PATH}" \
      --name "sslcertkey" \
      --password "${SSL_PASSWORD}" \
      --only-show-errors 2>/dev/null || echo "SSL 証明書の登録をスキップしました"

    echo "SSL 証明書の登録が完了しました。"
  fi
fi

echo "=== postprovision: 後処理が完了しました ==="
