using '../main.bicep'

// ============================================================================
// azd 用パラメータ（環境変数から読み込み）
// ============================================================================

param prefix = readEnvironmentVariable('AZURE_PREFIX', '')
param location = readEnvironmentVariable('AZURE_LOCATION', 'japaneast')

// VM
param vmPattern = int(readEnvironmentVariable('VM_PATTERN', '3'))
param cpuvmNumber = int(readEnvironmentVariable('CPUVM_NUMBER', '1'))
param gpuvmNumber = int(readEnvironmentVariable('GPUVM_NUMBER', '1'))
param cpuvmSku = readEnvironmentVariable('CPUVM_SKU', 'Standard_D8as_v5')
param gpuvmSku = readEnvironmentVariable('GPUVM_SKU', 'Standard_NC24ads_A100_v4')
param vmUser = readEnvironmentVariable('VM_USER', 'azureuser')
param cpuvmDataDiskSize = int(readEnvironmentVariable('CPUVM_DATADISK_SIZE', '512'))
param gpuvmDataDiskSize = int(readEnvironmentVariable('GPUVM_DATADISK_SIZE', '1536'))

// SSH
param sshPublicKey = readEnvironmentVariable('SSH_PUBLIC_KEY', '')

// ネットワーク
param hubAddressPrefix = readEnvironmentVariable('HUB_ADDRESS_PREFIX', '10.0.0.0/16')
param spokeAddressPrefix = readEnvironmentVariable('SPOKE_ADDRESS_PREFIX', '10.1.0.0/16')
param operatorAllowIps = [readEnvironmentVariable('OPERATOR_ALLOW_IP', '203.0.113.0/24')]
param customerAllowIps = [readEnvironmentVariable('CUSTOMER_ALLOW_IP', '192.0.2.0/24')]

// Microsoft Foundry
param enableFoundry = bool(readEnvironmentVariable('ENABLE_FOUNDRY', 'true'))
param foundryLocation = readEnvironmentVariable('FOUNDRY_LOCATION', 'eastus2')

// Application Gateway
param enableAppGateway = bool(readEnvironmentVariable('ENABLE_APP_GATEWAY', 'false'))
param domain = readEnvironmentVariable('DOMAIN', '.example.com')

// 監視・セキュリティ
param principalId = readEnvironmentVariable('AZURE_PRINCIPAL_ID', '')
param alertEmail = readEnvironmentVariable('ALERT_EMAIL', 'ops@example.com')
param enableBackup = bool(readEnvironmentVariable('ENABLE_BACKUP', 'true'))
param enableVmAutoStartStop = bool(readEnvironmentVariable('ENABLE_VM_AUTO_STOP', 'true'))
param vmStopTime = readEnvironmentVariable('VM_STOP_TIME', '1800')
param enableDefender = bool(readEnvironmentVariable('ENABLE_DEFENDER', 'false'))
param enableVmMonitoring = bool(readEnvironmentVariable('ENABLE_VM_MONITORING', 'false'))
param enableWorm = bool(readEnvironmentVariable('ENABLE_WORM', 'false'))
param wormRetentionDays = int(readEnvironmentVariable('WORM_RETENTION_DAYS', '7'))
