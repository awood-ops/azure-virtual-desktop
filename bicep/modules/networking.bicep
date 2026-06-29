// Verify latest AVM versions at:
// https://azure.github.io/Azure-Verified-Modules/indexes/bicep/bicep-resource-modules/

@description('Azure region')
param location string

@description('VNet address space (CIDR)')
param vnetAddressPrefix string = '10.20.0.0/16'

@description('Subnet for session host NICs')
param sessionHostSubnetPrefix string = '10.20.1.0/24'

@description('Subnet for private endpoints (storage, keyvault)')
param privateEndpointSubnetPrefix string = '10.20.2.0/24'

@description('Name prefix for all networking resources')
param namePrefix string

param tags object = {}

// ── NSG for session host subnet ───────────────────────────────────────────────

module nsg 'br/public:avm/res/network/network-security-group:0.4.0' = {
  name: 'nsg-session-hosts'
  params: {
    name: '${namePrefix}-nsg-hosts'
    location: location
    tags: tags
    securityRules: [
      {
        name: 'DenyInternetInbound'
        properties: {
          priority: 4000
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: 'Internet'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

// ── Virtual network ───────────────────────────────────────────────────────────

module vnet 'br/public:avm/res/network/virtual-network:0.4.0' = {
  name: 'vnet-avd'
  params: {
    name: '${namePrefix}-vnet'
    location: location
    tags: tags
    addressPrefixes: [ vnetAddressPrefix ]
    subnets: [
      {
        name: 'snet-avd-hosts'
        addressPrefix: sessionHostSubnetPrefix
        networkSecurityGroupResourceId: nsg.outputs.resourceId
      }
      {
        name: 'snet-avd-pe'
        addressPrefix: privateEndpointSubnetPrefix
        privateEndpointNetworkPolicies: 'Disabled'
      }
    ]
  }
}

output vnetId string = vnet.outputs.resourceId
output vnetName string = vnet.outputs.name
output sessionHostSubnetId string = vnet.outputs.subnetResourceIds[0]
output privateEndpointSubnetId string = vnet.outputs.subnetResourceIds[1]
