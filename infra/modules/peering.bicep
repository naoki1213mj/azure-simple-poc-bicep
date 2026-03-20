// ============================================================================
// VNet Peering モジュール（Hub ↔ Spoke 双方向）
// ============================================================================

@description('Hub VNet 名')
param hubVnetName string

@description('Hub VNet リソース ID')
param hubVnetId string

@description('Spoke VNet 名')
param spokeVnetName string

@description('Spoke VNet リソース ID')
param spokeVnetId string

@description('Spoke リソースグループ名')
param spokeRgName string

// ============================================================================
// Hub → Spoke Peering
// ============================================================================

resource hubToSpoke 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  name: '${hubVnetName}/peer-hub-to-spoke'
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
    remoteVirtualNetwork: {
      id: spokeVnetId
    }
  }
}

// ============================================================================
// Spoke → Hub Peering（クロスリソースグループ）
// ============================================================================

module spokeToHub 'spoke-peering.bicep' = {
  name: 'deploy-spoke-to-hub-peering'
  scope: resourceGroup(spokeRgName)
  params: {
    spokeVnetName: spokeVnetName
    hubVnetId: hubVnetId
  }
}
