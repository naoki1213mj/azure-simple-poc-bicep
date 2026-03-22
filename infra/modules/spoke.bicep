// ============================================================================
// Spoke モジュール - VNet, VM, Key Vault, Storage, Microsoft Foundry, 監視 (AVM)
// ============================================================================

@description('リソース命名プレフィックス')
param prefix string

@description('デプロイ先リージョン')
param location string

@description('リソースタグ')
param tags object

@description('Spoke VNet CIDR')
param spokeAddressPrefix string

@description('VM 管理者ユーザー名')
param vmUser string

@secure()
@description('SSH 公開鍵')
param sshPublicKey string

@description('VM 構成パターン')
param vmPattern int

@description('CPU VM 台数')
param cpuvmNumber int

@description('GPU VM 台数')
param gpuvmNumber int

@description('CPU VM SKU')
param cpuvmSku string

@description('GPU VM SKU')
param gpuvmSku string

@description('CPU VM データディスクサイズ')
param cpuvmDataDiskSize int

@description('GPU VM データディスクサイズ')
param gpuvmDataDiskSize int

@description('運用者グローバルIP')
param operatorAllowIps array

@description('デプロイ実行者のプリンシパルID')
param principalId string

@description('Microsoft Foundry 有効/無効')
param enableFoundry bool

@description('AI Services リージョン')
param foundryLocation string

@description('モデルデプロイ定義')
param modelDeployments array

@description('Azure Backup 有効/無効')
param enableBackup bool

@description('VM 自動起動停止')
param enableVmAutoStartStop bool

@description('VM 停止時刻')
param vmStopTime string

@description('VM 起動時刻')
param vmStartTime string

@description('WORM 有効/無効')
param enableWorm bool

@description('WORM 保持期間')
param wormRetentionDays int

@description('アラート通知先')
param alertEmail string

@description('VM 性能監視')
param enableVmMonitoring bool

@description('Hub Blob DNS Zone ID')
param hubDnsZoneBlobId string

@description('Hub CognitiveServices DNS Zone ID')
param hubDnsZoneCogServicesId string

@description('Hub Vault DNS Zone ID')
param hubDnsZoneVaultId string

// ============================================================================
// 変数
// ============================================================================

var vmSubnetPrefix = cidrSubnet(spokeAddressPrefix, 24, 0)
var pepSubnetPrefix = cidrSubnet(spokeAddressPrefix, 24, 1)
var deployCpuVm = vmPattern == 1 || vmPattern == 3
var deployGpuVm = vmPattern == 2 || vmPattern == 3

// GPU VM の cloud-init
var cloudConfigGpuVm = loadTextContent('cloud-init/gpu-vm.yaml')
var cloudConfigCpuVm = loadTextContent('cloud-init/cpu-vm.yaml')

// ============================================================================
// NSG - VM サブネット用 (AVM)
// ============================================================================

module nsgVm 'br/public:avm/res/network/network-security-group:0.5.0' = {
  name: 'deploy-nsg-vm'
  params: {
    name: 'nsg-vm-${prefix}-${location}-001'
    location: location
    tags: tags
    diagnosticSettings: [
      { workspaceResourceId: logAnalyticsWorkspaceId }
    ]
    securityRules: [
      { name: 'Allow-AzureLoadBalancer', properties: { priority: 100, direction: 'Inbound', access: 'Allow', protocol: '*', sourcePortRange: '*', destinationPortRange: '*', sourceAddressPrefix: 'AzureLoadBalancer', destinationAddressPrefix: '*' } }
      { name: 'Allow-Hub-Inbound', properties: { priority: 1000, direction: 'Inbound', access: 'Allow', protocol: '*', sourcePortRange: '*', destinationPortRange: '*', sourceAddressPrefix: '10.0.0.0/16', destinationAddressPrefix: '*' } }
      { name: 'Allow-Spoke-Inbound', properties: { priority: 1010, direction: 'Inbound', access: 'Allow', protocol: '*', sourcePortRange: '*', destinationPortRange: '*', sourceAddressPrefix: spokeAddressPrefix, destinationAddressPrefix: '*' } }
      { name: 'Deny-All-Inbound', properties: { priority: 4000, direction: 'Inbound', access: 'Deny', protocol: '*', sourcePortRange: '*', destinationPortRange: '*', sourceAddressPrefix: '*', destinationAddressPrefix: '*' } }
      { name: 'Allow-Internet-Outbound', properties: { priority: 100, direction: 'Outbound', access: 'Allow', protocol: '*', sourcePortRange: '*', destinationPortRange: '*', sourceAddressPrefix: '*', destinationAddressPrefix: 'Internet' } }
    ]
  }
}

// ============================================================================
// NSG - Private Endpoint サブネット用 (AVM)
// ============================================================================

module nsgPep 'br/public:avm/res/network/network-security-group:0.5.0' = {
  name: 'deploy-nsg-pep'
  params: {
    name: 'nsg-pep-${prefix}-${location}-001'
    location: location
    tags: tags
    diagnosticSettings: [
      { workspaceResourceId: logAnalyticsWorkspaceId }
    ]
    securityRules: [
      { name: 'Allow-VNet-Inbound', properties: { priority: 100, direction: 'Inbound', access: 'Allow', protocol: 'Tcp', sourcePortRange: '*', destinationPortRange: '443', sourceAddressPrefix: 'VirtualNetwork', destinationAddressPrefix: '*' } }
      { name: 'Deny-All-Inbound', properties: { priority: 4000, direction: 'Inbound', access: 'Deny', protocol: '*', sourcePortRange: '*', destinationPortRange: '*', sourceAddressPrefix: '*', destinationAddressPrefix: '*' } }
    ]
  }
}

// ============================================================================
// NAT Gateway (AVM)
// ============================================================================

module natGateway 'br/public:avm/res/network/nat-gateway:1.2.1' = {
  name: 'deploy-nat-gw'
  params: {
    name: 'nat-${prefix}-${location}-001'
    location: location
    tags: tags
    zone: 0
    publicIPAddressObjects: [
      { name: 'pip-nat-${prefix}-${location}-001' }
    ]
  }
}

// ============================================================================
// VNet - Spoke (AVM)
// ============================================================================

module vnet 'br/public:avm/res/network/virtual-network:0.5.2' = {
  name: 'deploy-vnet-spoke'
  params: {
    name: 'vnet-spoke-${prefix}-${location}-001'
    location: location
    tags: tags
    lock: { kind: 'CanNotDelete', name: 'lock-vnet-spoke' }
    diagnosticSettings: [
      { workspaceResourceId: logAnalyticsWorkspaceId }
    ]
    addressPrefixes: [spokeAddressPrefix]
    subnets: [
      {
        name: 'snet-vm-${prefix}-001'
        addressPrefix: vmSubnetPrefix
        networkSecurityGroupResourceId: nsgVm.outputs.resourceId
        natGatewayResourceId: natGateway.outputs.resourceId
      }
      {
        name: 'snet-pep-${prefix}-001'
        addressPrefix: pepSubnetPrefix
        networkSecurityGroupResourceId: nsgPep.outputs.resourceId
      }
    ]
  }
}

// ============================================================================
// Log Analytics（main.bicep から ID を受け取る）
// ============================================================================

@description('Log Analytics Workspace リソース ID')
param logAnalyticsWorkspaceId string

// ============================================================================
// Key Vault (AVM)
// ============================================================================

module keyVault 'br/public:avm/res/key-vault/vault:0.11.0' = {
  name: 'deploy-keyvault'
  params: {
    name: 'kv-${prefix}-${take(uniqueString(resourceGroup().id), 6)}'
    location: location
    tags: tags
    enableRbacAuthorization: true
    enablePurgeProtection: true
    softDeleteRetentionInDays: 90
    enableVaultForDiskEncryption: true
    enableVaultForTemplateDeployment: true
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
      ipRules: [for ip in operatorAllowIps: { value: ip }]
    }
    diagnosticSettings: [
      { workspaceResourceId: logAnalyticsWorkspaceId }
    ]
    lock: { kind: 'CanNotDelete', name: 'lock-kv' }
    roleAssignments: [
      {
        principalId: principalId
        roleDefinitionIdOrName: 'Key Vault Administrator'
        principalType: 'User'
      }
    ]
  }
}

// ============================================================================
// Storage Account (AVM)
// ============================================================================

module storageAccount 'br/public:avm/res/storage/storage-account:0.15.0' = {
  name: 'deploy-storage'
  params: {
    name: take('st${prefix}${uniqueString(resourceGroup().id)}', 24)
    location: location
    tags: tags
    skuName: 'Standard_LRS'
    kind: 'StorageV2'
    allowSharedKeyAccess: false
    requireInfrastructureEncryption: true
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    publicNetworkAccess: 'Disabled'
    networkAcls: { defaultAction: 'Deny', bypass: 'AzureServices' }
    blobServices: {
      deleteRetentionPolicyEnabled: true
      deleteRetentionPolicyDays: 7
      containerDeleteRetentionPolicyEnabled: true
      containerDeleteRetentionPolicyDays: 7
    }
    managementPolicyRules: enableWorm ? [
      {
        enabled: true
        name: 'worm-retention'
        type: 'Lifecycle'
        definition: {
          actions: {
            version: {
              delete: { daysAfterCreationGreaterThan: wormRetentionDays }
            }
          }
          filters: { blobTypes: ['blockBlob'] }
        }
      }
    ] : []
    diagnosticSettings: [
      { workspaceResourceId: logAnalyticsWorkspaceId }
    ]
    lock: { kind: 'CanNotDelete', name: 'lock-st' }
    privateEndpoints: [
      {
        subnetResourceId: vnet.outputs.subnetResourceIds[1]
        service: 'blob'
        privateDnsZoneGroup: {
          privateDnsZoneGroupConfigs: [
            { privateDnsZoneResourceId: hubDnsZoneBlobId }
          ]
        }
      }
    ]
  }
}

// ============================================================================
// CPU VM (AVM)
// ============================================================================

module cpuVm 'br/public:avm/res/compute/virtual-machine:0.12.0' = [for i in range(0, cpuvmNumber): if (deployCpuVm) {
  name: 'deploy-cpuvm-${i + 1}'
  params: {
    name: 'vm-cpu-${prefix}-${location}-${padLeft(string(i + 1), 3, '0')}'
    location: location
    tags: tags
    adminUsername: vmUser
    disablePasswordAuthentication: true
    publicKeys: [
      {
        keyData: sshPublicKey
        path: '/home/${vmUser}/.ssh/authorized_keys'
      }
    ]
    vmSize: cpuvmSku
    zone: 0
    osType: 'Linux'
    imageReference: {
      publisher: 'RedHat'
      offer: 'RHEL'
      sku: '94_gen2'
      version: 'latest'
    }
    osDisk: {
      diskSizeGB: 128
      managedDisk: { storageAccountType: 'StandardSSD_LRS' }
      deleteOption: 'Delete'
    }
    dataDisks: [
      {
        lun: 0
        diskSizeGB: cpuvmDataDiskSize
        managedDisk: { storageAccountType: 'StandardSSD_LRS' }
        createOption: 'Empty'
        deleteOption: 'Delete'
      }
    ]
    nicConfigurations: [
      {
        nicSuffix: '-nic'
        enableAcceleratedNetworking: true
        ipConfigurations: [
          {
            name: 'ipconfig1'
            subnetResourceId: vnet.outputs.subnetResourceIds[0] // snet-vm
          }
        ]
      }
    ]
    managedIdentities: { systemAssigned: true }
    securityType: 'TrustedLaunch'
    secureBootEnabled: true
    vTpmEnabled: true
    customData: cloudConfigCpuVm
    bootDiagnostics: true
    patchMode: 'AutomaticByPlatform'
  }
}]

// ============================================================================
// GPU VM (AVM)
// ============================================================================

module gpuVm 'br/public:avm/res/compute/virtual-machine:0.12.0' = [for i in range(0, gpuvmNumber): if (deployGpuVm) {
  name: 'deploy-gpuvm-${i + 1}'
  params: {
    name: 'vm-gpu-${prefix}-${location}-${padLeft(string(i + 1), 3, '0')}'
    location: location
    tags: tags
    adminUsername: vmUser
    disablePasswordAuthentication: true
    publicKeys: [
      {
        keyData: sshPublicKey
        path: '/home/${vmUser}/.ssh/authorized_keys'
      }
    ]
    vmSize: gpuvmSku
    zone: 0
    osType: 'Linux'
    imageReference: {
      publisher: 'RedHat'
      offer: 'RHEL'
      sku: '94_gen2'
      version: 'latest'
    }
    osDisk: {
      diskSizeGB: 1280
      managedDisk: { storageAccountType: 'StandardSSD_LRS' }
      deleteOption: 'Delete'
    }
    dataDisks: [
      {
        lun: 0
        diskSizeGB: gpuvmDataDiskSize
        managedDisk: { storageAccountType: 'StandardSSD_LRS' }
        createOption: 'Empty'
        deleteOption: 'Delete'
      }
    ]
    nicConfigurations: [
      {
        nicSuffix: '-nic'
        enableAcceleratedNetworking: true
        ipConfigurations: [
          {
            name: 'ipconfig1'
            subnetResourceId: vnet.outputs.subnetResourceIds[0]
          }
        ]
      }
    ]
    managedIdentities: { systemAssigned: true }
    securityType: 'TrustedLaunch'
    secureBootEnabled: false // NVIDIA ドライバ互換性のため
    vTpmEnabled: true
    customData: cloudConfigGpuVm
    bootDiagnostics: true
    patchMode: 'AutomaticByPlatform'
  }
}]

// ============================================================================
// VM 自動停止 (DevTestLab Schedule)
// ============================================================================

resource cpuVmStopSchedule 'Microsoft.DevTestLab/schedules@2018-09-15' = [for i in range(0, cpuvmNumber): if (deployCpuVm && enableVmAutoStartStop) {
  name: 'shutdown-computevm-vm-cpu-${prefix}-${location}-${padLeft(string(i + 1), 3, '0')}'
  location: location
  tags: tags
  properties: {
    status: 'Enabled'
    taskType: 'ComputeVmShutdownTask'
    dailyRecurrence: { time: vmStopTime }
    timeZoneId: 'Tokyo Standard Time'
    notificationSettings: { status: 'Disabled' }
    targetResourceId: cpuVm[i].outputs.resourceId
  }
}]

resource gpuVmStopSchedule 'Microsoft.DevTestLab/schedules@2018-09-15' = [for i in range(0, gpuvmNumber): if (deployGpuVm && enableVmAutoStartStop) {
  name: 'shutdown-computevm-vm-gpu-${prefix}-${location}-${padLeft(string(i + 1), 3, '0')}'
  location: location
  tags: tags
  properties: {
    status: 'Enabled'
    taskType: 'ComputeVmShutdownTask'
    dailyRecurrence: { time: vmStopTime }
    timeZoneId: 'Tokyo Standard Time'
    notificationSettings: { status: 'Disabled' }
    targetResourceId: gpuVm[i].outputs.resourceId
  }
}]

// ============================================================================
// AI Services (AVM) + Foundry Project
// ============================================================================

module aiServices 'br/public:avm/res/cognitive-services/account:0.10.0' = if (enableFoundry) {
  name: 'deploy-ai-services'
  params: {
    name: 'ais-${prefix}-${location}-001'
    location: foundryLocation
    tags: tags
    kind: 'AIServices'
    sku: 'S0'
    customSubDomainName: 'ais-${prefix}-${location}-001'
    managedIdentities: { systemAssigned: true }
    publicNetworkAccess: 'Disabled'
    networkAcls: { defaultAction: 'Deny' }
    deployments: [for model in modelDeployments: {
      name: model.name
      model: { format: 'OpenAI', name: model.name, version: model.version }
      sku: { name: model.sku, capacity: model.capacity }
    }]
    diagnosticSettings: [
      { workspaceResourceId: logAnalyticsWorkspaceId }
    ]
    privateEndpoints: [
      {
        subnetResourceId: vnet.outputs.subnetResourceIds[1]
        service: 'account'
        privateDnsZoneGroup: {
          privateDnsZoneGroupConfigs: [
            { privateDnsZoneResourceId: hubDnsZoneCogServicesId }
          ]
        }
      }
    ]
    roleAssignments: [for i in range(0, deployCpuVm ? cpuvmNumber : 0): {
      principalId: cpuVm[i].outputs.systemAssignedMIPrincipalId
      roleDefinitionIdOrName: 'Cognitive Services OpenAI User'
      principalType: 'ServicePrincipal'
    }]
  }
}

// ============================================================================
// Recovery Services Vault (AVM)
// ============================================================================

module recoveryVault 'br/public:avm/res/recovery-services/vault:0.11.0' = if (enableBackup) {
  name: 'deploy-recovery-vault'
  params: {
    name: 'rsv-${prefix}-${location}-001'
    location: location
    tags: tags
    lock: { kind: 'CanNotDelete', name: 'lock-rsv' }
  }
}

// ============================================================================
// Action Group（アラート通知先）
// ============================================================================

resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = if (enableVmMonitoring) {
  name: 'ag-${prefix}-${location}-001'
  location: 'global'
  tags: tags
  properties: {
    groupShortName: take(prefix, 12)
    enabled: true
    emailReceivers: [
      { name: 'ops-email', emailAddress: alertEmail, useCommonAlertSchema: true }
    ]
  }
}

// ============================================================================
// VM 性能監視アラート（Scheduled Query Rules）
// ============================================================================

var monitoringRules = [
  { name: 'CPU 使用率 > 90%', query: 'InsightsMetrics | where Namespace == "Processor" and Name == "UtilizationPercentage" | summarize avg(Val) by bin(TimeGenerated, 5m), Computer | where avg_Val > 90', severity: 2 }
  { name: 'メモリ使用率 > 90%', query: 'InsightsMetrics | where Namespace == "Memory" and Name == "AvailableMB" | extend totalMB = toreal(parse_json(Tags).["vm.azm.ms/memorySizeMB"]) | extend usedPct = (1 - Val / totalMB) * 100 | summarize avg(usedPct) by bin(TimeGenerated, 5m), Computer | where avg_usedPct > 90', severity: 2 }
  { name: 'ディスク使用率 > 85%', query: 'InsightsMetrics | where Namespace == "LogicalDisk" and Name == "FreeSpacePercentage" | summarize avg(Val) by bin(TimeGenerated, 5m), Computer | where avg_Val < 15', severity: 3 }
]

resource scheduledQueryRules 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = [for (rule, i) in monitoringRules: if (enableVmMonitoring) {
  name: 'sqr-${prefix}-${location}-${padLeft(string(i + 1), 2, '0')}'
  location: location
  tags: tags
  properties: {
    displayName: rule.name
    severity: rule.severity
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    scopes: [logAnalyticsWorkspaceId]
    targetResourceTypes: ['Microsoft.Compute/virtualMachines']
    criteria: {
      allOf: [
        {
          query: rule.query
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: { numberOfEvaluationPeriods: 3, minFailingPeriodsToAlert: 2 }
        }
      ]
    }
    actions: {
      actionGroups: enableVmMonitoring ? [actionGroup.id] : []
    }
  }
}]

// ============================================================================
// Azure Monitor Agent（VM Extension + Data Collection Rule）
// ============================================================================

resource dataCollectionEndpoint 'Microsoft.Insights/dataCollectionEndpoints@2022-06-01' = if (enableVmMonitoring) {
  name: 'dce-${prefix}-${location}-001'
  location: location
  tags: tags
  properties: {}
}

resource dataCollectionRule 'Microsoft.Insights/dataCollectionRules@2022-06-01' = if (enableVmMonitoring) {
  name: 'dcr-${prefix}-${location}-001'
  location: location
  tags: tags
  properties: {
    dataCollectionEndpointId: dataCollectionEndpoint.id
    dataSources: {
      performanceCounters: [
        {
          name: 'perfCounters'
          streams: ['Microsoft-Perf', 'Microsoft-InsightsMetrics']
          samplingFrequencyInSeconds: 60
          counterSpecifiers: [
            '\\Processor Information(_Total)\\% Processor Time'
            '\\Memory\\Available Bytes'
            '\\Memory\\% Committed Bytes In Use'
            '\\LogicalDisk(_Total)\\% Free Space'
            '\\LogicalDisk(_Total)\\Free Megabytes'
          ]
        }
      ]
      syslog: [
        {
          name: 'syslog'
          streams: ['Microsoft-Syslog']
          facilityNames: ['auth', 'authpriv', 'daemon', 'kern', 'syslog']
          logLevels: ['Warning', 'Error', 'Critical', 'Alert', 'Emergency']
        }
      ]
    }
    destinations: {
      logAnalytics: [
        { workspaceResourceId: logAnalyticsWorkspaceId, name: 'logAnalytics' }
      ]
    }
    dataFlows: [
      { streams: ['Microsoft-Perf', 'Microsoft-InsightsMetrics'], destinations: ['logAnalytics'] }
      { streams: ['Microsoft-Syslog'], destinations: ['logAnalytics'] }
    ]
  }
}

// CPU VM に AMA をインストール
resource cpuVmAma 'Microsoft.Compute/virtualMachines/extensions@2024-07-01' = [for i in range(0, cpuvmNumber): if (deployCpuVm && enableVmMonitoring) {
  name: 'vm-cpu-${prefix}-${location}-${padLeft(string(i + 1), 3, '0')}/AzureMonitorLinuxAgent'
  location: location
  tags: tags
  properties: {
    publisher: 'Microsoft.Azure.Monitor'
    type: 'AzureMonitorLinuxAgent'
    typeHandlerVersion: '1.0'
    autoUpgradeMinorVersion: true
    enableAutomaticUpgrade: true
  }
  dependsOn: [cpuVm[i]]
}]

// CPU VM に DCR を関連付け
resource cpuVmRef 'Microsoft.Compute/virtualMachines@2024-07-01' existing = [for i in range(0, cpuvmNumber): if (deployCpuVm) {
  name: 'vm-cpu-${prefix}-${location}-${padLeft(string(i + 1), 3, '0')}'
}]

resource cpuVmDcrAssociation 'Microsoft.Insights/dataCollectionRuleAssociations@2022-06-01' = [for i in range(0, cpuvmNumber): if (deployCpuVm && enableVmMonitoring) {
  name: 'dcr-assoc-cpuvm-${padLeft(string(i + 1), 3, '0')}'
  scope: cpuVmRef[i]
  properties: {
    dataCollectionRuleId: dataCollectionRule.id
  }
  dependsOn: [cpuVm[i]]
}]

// GPU VM に AMA をインストール
resource gpuVmAma 'Microsoft.Compute/virtualMachines/extensions@2024-07-01' = [for i in range(0, gpuvmNumber): if (deployGpuVm && enableVmMonitoring) {
  name: 'vm-gpu-${prefix}-${location}-${padLeft(string(i + 1), 3, '0')}/AzureMonitorLinuxAgent'
  location: location
  tags: tags
  properties: {
    publisher: 'Microsoft.Azure.Monitor'
    type: 'AzureMonitorLinuxAgent'
    typeHandlerVersion: '1.0'
    autoUpgradeMinorVersion: true
    enableAutomaticUpgrade: true
  }
  dependsOn: [gpuVm[i]]
}]

// GPU VM に DCR を関連付け
resource gpuVmRef 'Microsoft.Compute/virtualMachines@2024-07-01' existing = [for i in range(0, gpuvmNumber): if (deployGpuVm) {
  name: 'vm-gpu-${prefix}-${location}-${padLeft(string(i + 1), 3, '0')}'
}]

resource gpuVmDcrAssociation 'Microsoft.Insights/dataCollectionRuleAssociations@2022-06-01' = [for i in range(0, gpuvmNumber): if (deployGpuVm && enableVmMonitoring) {
  name: 'dcr-assoc-gpuvm-${padLeft(string(i + 1), 3, '0')}'
  scope: gpuVmRef[i]
  properties: {
    dataCollectionRuleId: dataCollectionRule.id
  }
  dependsOn: [gpuVm[i]]
}]

// ============================================================================
// VM 自動起動（Azure Automation）
// ============================================================================

resource automationAccount 'Microsoft.Automation/automationAccounts@2023-11-01' = if (enableVmAutoStartStop) {
  name: 'aa-${prefix}-${location}-001'
  location: location
  tags: tags
  identity: { type: 'SystemAssigned' }
  properties: {
    sku: { name: 'Basic' }
    encryption: { keySource: 'Microsoft.Automation' }
  }
}

// Automation に VM 起動権限を付与
resource automationRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableVmAutoStartStop) {
  name: guid(resourceGroup().id, automationAccount.id, 'vm-contributor')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '9980e02c-c2be-4d73-94e8-173b1dc7cf3c') // Virtual Machine Contributor
    principalId: automationAccount.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource startRunbook 'Microsoft.Automation/automationAccounts/runbooks@2023-11-01' = if (enableVmAutoStartStop) {
  parent: automationAccount
  name: 'StartVMs'
  location: location
  tags: tags
  properties: {
    runbookType: 'GraphPowerShell'
    publishContentLink: {
      uri: 'https://raw.githubusercontent.com/azureautomation/start-azure-v2-vms/master/StartAzureV2Vm.graphrunbook'
    }
  }
}

// CPU VM 起動スケジュール
resource cpuVmStartSchedule 'Microsoft.Automation/automationAccounts/schedules@2023-11-01' = [for i in range(0, cpuvmNumber): if (deployCpuVm && enableVmAutoStartStop) {
  parent: automationAccount
  name: 'start-cpuvm-${padLeft(string(i + 1), 3, '0')}'
  properties: {
    frequency: 'Day'
    interval: 1
    timeZone: 'Tokyo Standard Time'
  }
}]

// ============================================================================
// 出力
// ============================================================================

output vnetId string = vnet.outputs.resourceId
output vnetName string = vnet.outputs.name
output logAnalyticsWorkspaceId string = logAnalyticsWorkspaceId
output keyVaultName string = keyVault.outputs.name
output storageAccountName string = storageAccount.outputs.name
