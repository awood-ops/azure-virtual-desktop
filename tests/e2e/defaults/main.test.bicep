targetScope = 'subscription'

// namePrefix and location are injected by the CI workflow via --parameters.
// Format: avd{run_number}  (e.g. avd5432)
// The 'dfl' serviceShort suffix ensures globally-unique resource names when
// the max scenario runs in parallel.

@description('Short unique run prefix — provided by CI (e.g. avd5432).')
param namePrefix string

@description('Azure region for all test resources.')
param location string = 'uksouth'

var serviceShort      = 'dfl'
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
    // Networking
    deployNetworking:           true
    vnetAddressPrefix:          '10.240.0.0/16'
    sessionHostSubnetPrefix:    '10.240.1.0/24'
    privateEndpointSubnetPrefix:'10.240.2.0/24'
    // Key Vault
    deployKeyVault:             true
    adminUsername:              'avdadmin'
    // Storage — no private endpoint in defaults (saves needing a DNS zone)
    deployStorage:              true
    filePrivateDnsZoneId:       ''
    // AVD control plane
    hostPoolType:               'Pooled'
    maxSessionLimit:            2
    deployScalingPlan:          false
    // Session hosts — skipped in defaults (faster + cheaper)
    deploySessionHosts:         false
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

