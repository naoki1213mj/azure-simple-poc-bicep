// ============================================================================
// Spoke → Hub Peering（Spoke リソースグループスコープ）
// ============================================================================

@description('Spoke VNet 名')
param spokeVnetName string

@description('Hub VNet リソース ID')
param hubVnetId string

resource spokeToHub 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  name: '${spokeVnetName}/peer-spoke-to-hub'
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
    remoteVirtualNetwork: {
      id: hubVnetId
    }
  }
}
