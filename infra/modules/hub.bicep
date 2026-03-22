// ============================================================================
// Hub モジュール - VNet, Bastion, Application Gateway (AVM)
// ============================================================================

@description('リソース命名プレフィックス')
param prefix string

@description('デプロイ先リージョン')
param location string

@description('リソースタグ')
param tags object

@description('Hub VNet CIDR')
param hubAddressPrefix string

@description('運用者グローバルIP')
param operatorAllowIps array

@description('エンドユーザーグローバルIP')
param customerAllowIps array

@description('Application Gateway の有効/無効')
param enableAppGateway bool

@description('Log Analytics Workspace リソース ID')
param logAnalyticsWorkspaceId string

// ============================================================================
// 変数
// ============================================================================

var bastionSubnetPrefix = cidrSubnet(hubAddressPrefix, 26, 0)  // /26
var agwSubnetPrefix = cidrSubnet(hubAddressPrefix, 24, 1)       // /24

// ============================================================================
// NSG - Bastion サブネット用 (AVM)
// ============================================================================

module nsgBastion 'br/public:avm/res/network/network-security-group:0.5.0' = {
  name: 'deploy-nsg-bastion'
  params: {
    name: 'nsg-bas-${prefix}-${location}-001'
    location: location
    tags: tags
    diagnosticSettings: [
      { workspaceResourceId: logAnalyticsWorkspaceId }
    ]
    securityRules: [
      { name: 'Allow-GatewayManager-Inbound', properties: { priority: 100, direction: 'Inbound', access: 'Allow', protocol: 'Tcp', sourcePortRange: '*', destinationPortRange: '443', sourceAddressPrefix: 'GatewayManager', destinationAddressPrefix: '*' } }
      { name: 'Allow-AzureLoadBalancer-Inbound', properties: { priority: 110, direction: 'Inbound', access: 'Allow', protocol: 'Tcp', sourcePortRange: '*', destinationPortRange: '443', sourceAddressPrefix: 'AzureLoadBalancer', destinationAddressPrefix: '*' } }
      { name: 'Allow-Operator-Inbound', properties: { priority: 120, direction: 'Inbound', access: 'Allow', protocol: 'Tcp', sourcePortRange: '*', destinationPortRange: '443', sourceAddressPrefixes: operatorAllowIps, destinationAddressPrefix: '*' } }
      { name: 'Allow-BastionHost-Inbound', properties: { priority: 130, direction: 'Inbound', access: 'Allow', protocol: '*', sourcePortRange: '*', destinationPortRanges: ['8080', '5701'], sourceAddressPrefix: 'VirtualNetwork', destinationAddressPrefix: 'VirtualNetwork' } }
      { name: 'Deny-All-Inbound', properties: { priority: 4000, direction: 'Inbound', access: 'Deny', protocol: '*', sourcePortRange: '*', destinationPortRange: '*', sourceAddressPrefix: '*', destinationAddressPrefix: '*' } }
      { name: 'Allow-SSH-RDP-Outbound', properties: { priority: 100, direction: 'Outbound', access: 'Allow', protocol: '*', sourcePortRange: '*', destinationPortRanges: ['22', '3389'], sourceAddressPrefix: '*', destinationAddressPrefix: 'VirtualNetwork' } }
      { name: 'Allow-AzureCloud-Outbound', properties: { priority: 110, direction: 'Outbound', access: 'Allow', protocol: 'Tcp', sourcePortRange: '*', destinationPortRange: '443', sourceAddressPrefix: '*', destinationAddressPrefix: 'AzureCloud' } }
      { name: 'Allow-BastionHost-Outbound', properties: { priority: 120, direction: 'Outbound', access: 'Allow', protocol: '*', sourcePortRange: '*', destinationPortRanges: ['8080', '5701'], sourceAddressPrefix: 'VirtualNetwork', destinationAddressPrefix: 'VirtualNetwork' } }
      { name: 'Allow-Session-Outbound', properties: { priority: 130, direction: 'Outbound', access: 'Allow', protocol: 'Tcp', sourcePortRange: '*', destinationPortRange: '80', sourceAddressPrefix: '*', destinationAddressPrefix: 'Internet' } }
      { name: 'Deny-All-Outbound', properties: { priority: 4000, direction: 'Outbound', access: 'Deny', protocol: '*', sourcePortRange: '*', destinationPortRange: '*', sourceAddressPrefix: '*', destinationAddressPrefix: '*' } }
    ]
  }
}

// ============================================================================
// NSG - Application Gateway サブネット用 (AVM)
// ============================================================================

module nsgAppGw 'br/public:avm/res/network/network-security-group:0.5.0' = if (enableAppGateway) {
  name: 'deploy-nsg-agw'
  params: {
    name: 'nsg-agw-${prefix}-${location}-001'
    location: location
    tags: tags
    diagnosticSettings: [
      { workspaceResourceId: logAnalyticsWorkspaceId }
    ]
    securityRules: [
      { name: 'Allow-GatewayManager', properties: { priority: 100, direction: 'Inbound', access: 'Allow', protocol: '*', sourcePortRange: '*', destinationPortRange: '65200-65535', sourceAddressPrefix: 'GatewayManager', destinationAddressPrefix: '*' } }
      { name: 'Allow-AzureLoadBalancer', properties: { priority: 110, direction: 'Inbound', access: 'Allow', protocol: '*', sourcePortRange: '*', destinationPortRange: '*', sourceAddressPrefix: 'AzureLoadBalancer', destinationAddressPrefix: '*' } }
      { name: 'Allow-Operator-HTTPS', properties: { priority: 120, direction: 'Inbound', access: 'Allow', protocol: 'Tcp', sourcePortRange: '*', destinationPortRanges: ['80', '443'], sourceAddressPrefixes: operatorAllowIps, destinationAddressPrefix: '*' } }
      { name: 'Allow-Customer-HTTPS', properties: { priority: 130, direction: 'Inbound', access: 'Allow', protocol: 'Tcp', sourcePortRange: '*', destinationPortRanges: ['80', '443'], sourceAddressPrefixes: customerAllowIps, destinationAddressPrefix: '*' } }
      { name: 'Deny-All-Inbound', properties: { priority: 4000, direction: 'Inbound', access: 'Deny', protocol: '*', sourcePortRange: '*', destinationPortRange: '*', sourceAddressPrefix: '*', destinationAddressPrefix: '*' } }
    ]
  }
}

// ============================================================================
// VNet - Hub (AVM)
// ============================================================================

module vnet 'br/public:avm/res/network/virtual-network:0.5.2' = {
  name: 'deploy-vnet-hub'
  params: {
    name: 'vnet-hub-${prefix}-${location}-001'
    location: location
    tags: tags
    lock: { kind: 'CanNotDelete', name: 'lock-vnet-hub' }
    diagnosticSettings: [
      { workspaceResourceId: logAnalyticsWorkspaceId }
    ]
    addressPrefixes: [hubAddressPrefix]
    subnets: union(
      [
        {
          name: 'AzureBastionSubnet'
          addressPrefix: bastionSubnetPrefix
          networkSecurityGroupResourceId: nsgBastion.outputs.resourceId
        }
      ],
      enableAppGateway ? [
        {
          name: 'snet-agw-${prefix}-001'
          addressPrefix: agwSubnetPrefix
          networkSecurityGroupResourceId: nsgAppGw.outputs.resourceId
        }
      ] : []
    )
  }
}

// ============================================================================
// Bastion (AVM)
// ============================================================================

module bastion 'br/public:avm/res/network/bastion-host:0.6.0' = {
  name: 'deploy-bastion'
  params: {
    name: 'bas-${prefix}-${location}-001'
    location: location
    tags: tags
    virtualNetworkResourceId: vnet.outputs.resourceId
    skuName: 'Standard'
    scaleUnits: 2
    enableFileCopy: true
    enableIpConnect: true
    enableKerberos: false
    lock: { kind: 'CanNotDelete', name: 'lock-bastion' }
    diagnosticSettings: [
      { workspaceResourceId: logAnalyticsWorkspaceId }
    ]
  }
}

// ============================================================================
// Private DNS Zones (AVM)
// ============================================================================

module dnsZoneBlob 'br/public:avm/res/network/private-dns-zone:0.7.0' = {
  name: 'deploy-pdz-blob'
  params: {
    name: 'privatelink.blob.${environment().suffixes.storage}'
    tags: tags
    lock: { kind: 'CanNotDelete', name: 'lock-pdz-blob' }
    virtualNetworkLinks: [
      { virtualNetworkResourceId: vnet.outputs.resourceId, registrationEnabled: false }
    ]
  }
}

module dnsZoneCogServices 'br/public:avm/res/network/private-dns-zone:0.7.0' = {
  name: 'deploy-pdz-cogservices'
  params: {
    name: 'privatelink.cognitiveservices.azure.com'
    tags: tags
    lock: { kind: 'CanNotDelete', name: 'lock-pdz-cog' }
    virtualNetworkLinks: [
      { virtualNetworkResourceId: vnet.outputs.resourceId, registrationEnabled: false }
    ]
  }
}

module dnsZoneVault 'br/public:avm/res/network/private-dns-zone:0.7.0' = {
  name: 'deploy-pdz-vault'
  params: {
    name: 'privatelink.vaultcore.azure.net'
    tags: tags
    lock: { kind: 'CanNotDelete', name: 'lock-pdz-vault' }
    virtualNetworkLinks: [
      { virtualNetworkResourceId: vnet.outputs.resourceId, registrationEnabled: false }
    ]
  }
}

// ============================================================================
// Application Gateway + WAF Policy (AVM) ※オプション
// ============================================================================

resource wafPolicy 'Microsoft.Network/ApplicationGatewayWebApplicationFirewallPolicies@2024-05-01' = if (enableAppGateway) {
  name: 'wafpol-${prefix}-${location}-001'
  location: location
  tags: tags
  properties: {
    policySettings: {
      requestBodyCheck: true
      maxRequestBodySizeInKb: 128
      fileUploadLimitInMb: 100
      state: 'Enabled'
      mode: 'Prevention'
    }
    managedRules: {
      managedRuleSets: [
        { ruleSetType: 'Microsoft_DefaultRuleSet', ruleSetVersion: '2.1' }
        { ruleSetType: 'Microsoft_BotManagerRuleSet', ruleSetVersion: '1.1' }
      ]
    }
  }
}

resource agwPip 'Microsoft.Network/publicIPAddresses@2024-05-01' = if (enableAppGateway) {
  name: 'pip-agw-${prefix}-${location}-001'
  location: location
  tags: tags
  sku: { name: 'Standard' }
  properties: { publicIPAllocationMethod: 'Static' }
}

resource appGateway 'Microsoft.Network/applicationGateways@2024-05-01' = if (enableAppGateway) {
  name: 'agw-${prefix}-${location}-001'
  location: location
  tags: tags
  properties: {
    sku: { name: 'WAF_v2', tier: 'WAF_v2', capacity: 1 }
    gatewayIPConfigurations: [
      { name: 'appGwIpConfig', properties: { subnet: { id: vnet.outputs.subnetResourceIds[1] } } }
    ]
    frontendIPConfigurations: [
      { name: 'appGwFrontendIp', properties: { publicIPAddress: { id: agwPip.id } } }
    ]
    frontendPorts: [
      { name: 'port_80', properties: { port: 80 } }
    ]
    backendAddressPools: [
      { name: 'defaultBackendPool' }
    ]
    backendHttpSettingsCollection: [
      { name: 'defaultHttpSettings', properties: { port: 8080, protocol: 'Http', cookieBasedAffinity: 'Disabled', requestTimeout: 30 } }
    ]
    httpListeners: [
      { name: 'httpListener', properties: { frontendIPConfiguration: { id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', 'agw-${prefix}-${location}-001', 'appGwFrontendIp') }, frontendPort: { id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', 'agw-${prefix}-${location}-001', 'port_80') }, protocol: 'Http' } }
    ]
    requestRoutingRules: [
      { name: 'defaultRule', properties: { priority: 100, ruleType: 'Basic', httpListener: { id: resourceId('Microsoft.Network/applicationGateways/httpListeners', 'agw-${prefix}-${location}-001', 'httpListener') }, backendAddressPool: { id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', 'agw-${prefix}-${location}-001', 'defaultBackendPool') }, backendHttpSettings: { id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', 'agw-${prefix}-${location}-001', 'defaultHttpSettings') } } }
    ]
    firewallPolicy: { id: wafPolicy.id }
  }
}

// ============================================================================
// 出力
// ============================================================================

output vnetId string = vnet.outputs.resourceId
output vnetName string = vnet.outputs.name
output bastionName string = bastion.outputs.name
output dnsZoneBlobId string = dnsZoneBlob.outputs.resourceId
output dnsZoneBlobName string = dnsZoneBlob.outputs.name
output dnsZoneCogServicesId string = dnsZoneCogServices.outputs.resourceId
output dnsZoneCogServicesName string = dnsZoneCogServices.outputs.name
output dnsZoneVaultId string = dnsZoneVault.outputs.resourceId
output dnsZoneVaultName string = dnsZoneVault.outputs.name
output agwSubnetId string = enableAppGateway ? vnet.outputs.subnetResourceIds[1] : ''
