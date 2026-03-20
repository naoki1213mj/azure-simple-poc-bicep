using '../main.bicep'

// ============================================================================
// dev 環境パラメータ（最小構成）
// ============================================================================

param prefix = 'dev0001'
param location = 'japaneast'

// VM（CPU のみ）
param vmPattern = 1
param cpuvmNumber = 1
param gpuvmNumber = 0
param cpuvmSku = 'Standard_D4as_v5'
param cpuvmDataDiskSize = 256
param vmUser = 'azureuser'
param sshPublicKey = 'REPLACE_VIA_CI_OR_CLI'

// ネットワーク
param operatorAllowIps = ['203.0.113.0/24']
param customerAllowIps = ['192.0.2.0/24']

// AI Foundry
param enableFoundry = true
param foundryLocation = 'eastus2'
param modelDeployments = [
  { name: 'gpt-5.4-mini', version: '2025-10-01', sku: 'GlobalStandard', capacity: 10 }
]

// Application Gateway（dev は無効）
param enableAppGateway = false

// 監視（最小限）
param principalId = 'REPLACE_VIA_CI_OR_CLI'
param alertEmail = 'ops@example.com'
param enableBackup = false
param enableVmAutoStartStop = true
param vmStopTime = '1900'
param enableDefender = false
param enableVmMonitoring = false
param enableWorm = false
param wormRetentionDays = 1
