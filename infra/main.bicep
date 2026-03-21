// ============================================================================
// メインテンプレート - Hub-Spoke PoC 環境 (Azure Verified Modules)
// ============================================================================
targetScope = 'subscription'

// ============================================================================
// パラメーター定義 - 基本設定
// ============================================================================

@minLength(3)
@maxLength(7)
@description('リソース命名プレフィックス（英小文字/数字）')
param prefix string

@description('デプロイ先リージョン')
param location string = 'japaneast'

@description('VM 管理者ユーザー名')
param vmUser string = 'azureuser'

// ============================================================================
// パラメーター定義 - VM 構成
// ============================================================================

@description('VM 構成パターン (1:CPU / 2:GPU / 3:両方)')
@allowed([1, 2, 3])
param vmPattern int = 3

@description('CPU VM の台数')
param cpuvmNumber int = 1

@description('GPU VM の台数')
param gpuvmNumber int = 1

@description('CPU VM の SKU')
param cpuvmSku string = 'Standard_D8as_v5'

@description('GPU VM の SKU')
param gpuvmSku string = 'Standard_NC24ads_A100_v4'

@description('CPU VM のデータディスクサイズ (GB)')
param cpuvmDataDiskSize int = 512

@description('GPU VM のデータディスクサイズ (GB)')
param gpuvmDataDiskSize int = 1536

// ============================================================================
// パラメーター定義 - SSH
// ============================================================================

@secure()
@description('SSH 公開鍵')
param sshPublicKey string

// ============================================================================
// パラメーター定義 - ネットワーク
// ============================================================================

@description('Hub VNet CIDR')
param hubAddressPrefix string = '10.0.0.0/16'

@description('Spoke VNet CIDR')
param spokeAddressPrefix string = '10.1.0.0/16'

@description('運用者のグローバル IP アドレス一覧')
param operatorAllowIps array = []

@description('エンドユーザーのグローバル IP アドレス一覧')
param customerAllowIps array = []

// ============================================================================
// パラメーター定義 - Microsoft Foundry
// ============================================================================

@description('Microsoft Foundry の有効/無効')
param enableFoundry bool = true

@description('AI Services リソースのリージョン')
param foundryLocation string = 'eastus2'

@description('デプロイするモデル定義')
param modelDeployments array = [
  { name: 'gpt-5', version: '2025-06-18', sku: 'GlobalStandard', capacity: 10 }
  { name: 'gpt-5.4', version: '2025-10-01', sku: 'GlobalStandard', capacity: 10 }
  { name: 'gpt-5.4-mini', version: '2025-10-01', sku: 'GlobalStandard', capacity: 10 }
]

// ============================================================================
// パラメーター定義 - Application Gateway
// ============================================================================

@description('Application Gateway の有効/無効')
param enableAppGateway bool = false

@description('ドメイン名')
param domain string = '.example.com'

// ============================================================================
// パラメーター定義 - セキュリティ・監視
// ============================================================================

@description('デプロイ実行者のプリンシパル ID')
param principalId string

@description('アラート通知先メールアドレス')
param alertEmail string = 'ops@example.com'

@description('Azure Backup の有効/無効')
param enableBackup bool = true

@description('VM 自動起動停止の有効/無効')
param enableVmAutoStartStop bool = true

@description('VM 停止時刻 (HHmm)')
param vmStopTime string = '1800'

@description('Microsoft Defender for Cloud の有効/無効')
param enableDefender bool = false

@description('VM 性能監視の有効/無効')
param enableVmMonitoring bool = false

@description('ストレージ不変性ポリシー(WORM)の有効/無効')
param enableWorm bool = false

@description('WORM 保持期間（日）')
param wormRetentionDays int = 7

// ============================================================================
// 変数定義
// ============================================================================

var tags = {
  project: prefix
  managedBy: 'bicep-avm'
  architecture: 'hub-spoke-poc'
}

var hubRgName = 'rg-hub-${prefix}-${location}-001'
var spokeRgName = 'rg-spoke-${prefix}-${location}-001'

// ============================================================================
// リソースグループ
// ============================================================================

resource hubRg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: hubRgName
  location: location
  tags: tags
}

resource spokeRg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: spokeRgName
  location: location
  tags: tags
}

// ============================================================================
// Hub モジュール（Peering なしで先にデプロイ）
// ============================================================================

module hub 'modules/hub.bicep' = {
  name: 'deploy-hub'
  scope: hubRg
  params: {
    prefix: prefix
    location: location
    tags: tags
    hubAddressPrefix: hubAddressPrefix
    operatorAllowIps: operatorAllowIps
    customerAllowIps: customerAllowIps
    enableAppGateway: enableAppGateway
  }
}

// ============================================================================
// Spoke モジュール（Peering なしで先にデプロイ）
// ============================================================================

module spoke 'modules/spoke.bicep' = {
  name: 'deploy-spoke'
  scope: spokeRg
  params: {
    prefix: prefix
    location: location
    tags: tags
    spokeAddressPrefix: spokeAddressPrefix
    vmUser: vmUser
    sshPublicKey: sshPublicKey
    vmPattern: vmPattern
    cpuvmNumber: cpuvmNumber
    gpuvmNumber: gpuvmNumber
    cpuvmSku: cpuvmSku
    gpuvmSku: gpuvmSku
    cpuvmDataDiskSize: cpuvmDataDiskSize
    gpuvmDataDiskSize: gpuvmDataDiskSize
    operatorAllowIps: operatorAllowIps
    principalId: principalId
    enableFoundry: enableFoundry
    foundryLocation: foundryLocation
    modelDeployments: modelDeployments
    enableBackup: enableBackup
    enableVmAutoStartStop: enableVmAutoStartStop
    vmStopTime: vmStopTime
    enableWorm: enableWorm
    wormRetentionDays: wormRetentionDays
    alertEmail: alertEmail
    enableVmMonitoring: enableVmMonitoring
    hubDnsZoneBlobId: hub.outputs.dnsZoneBlobId
    hubDnsZoneCogServicesId: hub.outputs.dnsZoneCogServicesId
    hubDnsZoneVaultId: hub.outputs.dnsZoneVaultId
  }
}

// ============================================================================
// VNet Peering（両 VNet デプロイ後に設定）
// ============================================================================

module peering 'modules/peering.bicep' = {
  name: 'deploy-peering'
  scope: hubRg
  params: {
    hubVnetName: hub.outputs.vnetName
    hubVnetId: hub.outputs.vnetId
    spokeVnetName: spoke.outputs.vnetName
    spokeVnetId: spoke.outputs.vnetId
    spokeRgName: spokeRgName
  }
}

// ============================================================================
// Private DNS Zone - Spoke VNet リンク（Hub/Spoke 両方デプロイ後に追加）
// ============================================================================

module dnsLinkBlobSpoke 'br/public:avm/res/network/private-dns-zone:0.7.0' = {
  name: 'update-pdz-blob-spoke-link'
  scope: hubRg
  params: {
    name: hub.outputs.dnsZoneBlobName
    virtualNetworkLinks: [
      { virtualNetworkResourceId: hub.outputs.vnetId, registrationEnabled: false }
      { virtualNetworkResourceId: spoke.outputs.vnetId, registrationEnabled: false }
    ]
  }
}

module dnsLinkCogSpoke 'br/public:avm/res/network/private-dns-zone:0.7.0' = {
  name: 'update-pdz-cog-spoke-link'
  scope: hubRg
  params: {
    name: hub.outputs.dnsZoneCogServicesName
    virtualNetworkLinks: [
      { virtualNetworkResourceId: hub.outputs.vnetId, registrationEnabled: false }
      { virtualNetworkResourceId: spoke.outputs.vnetId, registrationEnabled: false }
    ]
  }
}

module dnsLinkVaultSpoke 'br/public:avm/res/network/private-dns-zone:0.7.0' = {
  name: 'update-pdz-vault-spoke-link'
  scope: hubRg
  params: {
    name: hub.outputs.dnsZoneVaultName
    virtualNetworkLinks: [
      { virtualNetworkResourceId: hub.outputs.vnetId, registrationEnabled: false }
      { virtualNetworkResourceId: spoke.outputs.vnetId, registrationEnabled: false }
    ]
  }
}

// ============================================================================
// Defender for Cloud (サブスクリプションスコープ)
// ============================================================================

resource defenderPricing 'Microsoft.Security/pricings@2024-01-01' = if (enableDefender) {
  name: 'VirtualMachines'
  properties: {
    pricingTier: 'Standard'
    subPlan: 'P1'
  }
}

// ============================================================================
// 出力
// ============================================================================

output hubResourceGroup string = hubRgName
output spokeResourceGroup string = spokeRgName
output bastionName string = hub.outputs.bastionName
output logAnalyticsWorkspaceId string = spoke.outputs.logAnalyticsWorkspaceId
output hubVnetName string = hub.outputs.vnetName
output spokeVnetName string = spoke.outputs.vnetName
