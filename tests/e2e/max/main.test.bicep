targetScope = 'subscription'

// namePrefix and location are injected by the CI workflow via --parameters.
// The 'max' serviceShort suffix ensures globally-unique resource names when
// the defaults scenario runs in parallel.

@description('Short unique run prefix — provided by CI (e.g. avd5432).')
param namePrefix string

@description('Azure region for all test resources.')
param location string = 'uksouth'

var serviceShort      = 'max'
var moduleNamePrefix  = '${namePrefix}${serviceShort}'
var resourceGroupName = 'dep-${namePrefix}-avd-${serviceShort}'

resource testRg 'Microsoft.Resources/resourceGroups@2024-07-01' = {
  name: resourceGroupName
  location: location
}

module avd '../../../bicep/main.bicep' = {
  scope: testRg
  name: '${uniqueString(deployment().name)}-avd-${serviceShort}'
  params: {
    namePrefix:                 moduleNamePrefix
    environment:                'test'
    // Networking — different CIDR from defaults so concurrent runs don't overlap
    deployNetworking:           true
    vnetAddressPrefix:          '10.241.0.0/16'
    sessionHostSubnetPrefix:    '10.241.1.0/24'
    privateEndpointSubnetPrefix:'10.241.2.0/24'
    // Key Vault
    deployKeyVault:             true
    adminUsername:              'avdadmin'
    // Storage — no private endpoint (saves needing a DNS zone)
    deployStorage:              true
    filePrivateDnsZoneId:       ''
    // AVD control plane — full features
    hostPoolType:               'Pooled'
    maxSessionLimit:            2
    deployScalingPlan:          true
    scalingPlanTimeZone:        'GMT Standard Time'
    // Session hosts — 1 VM, smaller size to keep cost manageable
    deploySessionHosts:         true
    sessionHostCount:           1
    vmSize:                     'Standard_D2s_v5'
    tags: {
      environment:   'test'
      managedBy:     'bicep'
      repo:          'azure-virtual-desktop'
      testScenario:  serviceShort
    }
  }
}

output resourceGroupName string = testRg.name
output moduleNamePrefix  string = moduleNamePrefix
