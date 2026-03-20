using '../main.bicep'

// ============================================================================
// prod 環境パラメータ（フル構成）
// ============================================================================

param prefix = 'prd0001'
param location = 'japaneast'

// VM（CPU + GPU）
param vmPattern = 3
param cpuvmNumber = 1
param gpuvmNumber = 1
param cpuvmSku = 'Standard_D8as_v5'
param gpuvmSku = 'Standard_NC24ads_A100_v4'
param cpuvmDataDiskSize = 512
param gpuvmDataDiskSize = 1536
param vmUser = 'azureuser'
param sshPublicKey = 'REPLACE_VIA_CI_OR_CLI'

// ネットワーク
param hubAddressPrefix = '10.0.0.0/16'
param spokeAddressPrefix = '10.1.0.0/16'
param operatorAllowIps = ['203.0.113.0/24']
param customerAllowIps = ['198.51.100.0/24']

// Microsoft Foundry
param enableFoundry = true
param foundryLocation = 'eastus2'
param modelDeployments = [
  { name: 'gpt-5', version: '2025-06-18', sku: 'GlobalStandard', capacity: 10 }
  { name: 'gpt-5.4', version: '2025-10-01', sku: 'GlobalStandard', capacity: 10 }
  { name: 'gpt-5.4-mini', version: '2025-10-01', sku: 'GlobalStandard', capacity: 10 }
]

// Application Gateway（prod は有効）
param enableAppGateway = true
param domain = '.example.com'

// 監視・セキュリティ（フル有効）
param principalId = 'REPLACE_VIA_CI_OR_CLI'
param alertEmail = 'ops@example.com'
param enableBackup = true
param enableVmAutoStartStop = false
param enableDefender = true
param enableVmMonitoring = true
param enableWorm = true
param wormRetentionDays = 30
