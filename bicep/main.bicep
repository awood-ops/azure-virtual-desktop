// Verify latest AVM versions at:
// https://azure.github.io/Azure-Verified-Modules/indexes/bicep/bicep-resource-modules/

targetScope = 'resourceGroup'

@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Short name prefix used across all resource names (e.g. avd-prd)')
param namePrefix string

// ── Networking ────────────────────────────────────────────────────────────────

@description('Deploy a new VNet, or set to false and provide existingSubnetId')
param deployNetworking bool = true

param vnetAddressPrefix string = '10.20.0.0/16'
param sessionHostSubnetPrefix string = '10.20.1.0/24'
param privateEndpointSubnetPrefix string = '10.20.2.0/24'

@description('Existing subnet ID — used when deployNetworking is false')
param existingSubnetId string = ''

// ── Key Vault & credentials ───────────────────────────────────────────────────

@description('Deploy Key Vault and auto-generate the VM admin password')
param deployKeyVault bool = true

@description('Local admin username for session host VMs')
param adminUsername string = 'avdadmin'

@description('Object IDs granted read access to the Key Vault (e.g. ops team group)')
param kvReaderPrincipalIds array = []

// ── Storage (FSLogix) ─────────────────────────────────────────────────────────

@description('Deploy Azure Files storage for FSLogix profiles')
param deployStorage bool = true

@description('Private DNS zone resource ID for file.core.windows.net (leave empty to skip PE)')
param filePrivateDnsZoneId string = ''

// ── AVD Control Plane ─────────────────────────────────────────────────────────

@allowed(['Pooled', 'Personal'])
param hostPoolType string = 'Pooled'

param maxSessionLimit int = 10
param deployScalingPlan bool = true
param scalingPlanTimeZone string = 'GMT Standard Time'

// ── Session Hosts ─────────────────────────────────────────────────────────────

@description('Deploy session host VMs in this run')
param deploySessionHosts bool = true

param sessionHostCount int = 2
param vmSize string = 'Standard_D4s_v5'

// ── Monitoring ────────────────────────────────────────────────────────────────

param logAnalyticsWorkspaceId string = ''

// ── Shared ────────────────────────────────────────────────────────────────────

param environment string

param tags object = {
  environment: environment
  managedBy: 'bicep'
  repo: 'azure-virtual-desktop'
}

// ── Networking ────────────────────────────────────────────────────────────────

module networking 'modules/networking.bicep' = if (deployNetworking) {
  name: 'networking'
  params: {
    location: location
    namePrefix: namePrefix
    vnetAddressPrefix: vnetAddressPrefix
    sessionHostSubnetPrefix: sessionHostSubnetPrefix
    privateEndpointSubnetPrefix: privateEndpointSubnetPrefix
    tags: tags
  }
}

var subnetId = deployNetworking ? networking.outputs.sessionHostSubnetId : existingSubnetId
var peSubnetId = deployNetworking ? networking.outputs.privateEndpointSubnetId : existingSubnetId

// ── Key Vault ─────────────────────────────────────────────────────────────────

module kvModule 'modules/keyvault.bicep' = if (deployKeyVault) {
  name: 'keyvault'
  params: {
    location: location
    namePrefix: namePrefix
    readerPrincipalIds: kvReaderPrincipalIds
    tags: tags
  }
}

// Reference existing Key Vault to use getSecret() — works whether we just created
// it or it already existed from a previous deployment
resource kv 'Microsoft.KeyVault/vaults@2023-07-01' existing = if (deployKeyVault) {
  name: deployKeyVault ? kvModule.outputs.keyVaultName : 'placeholder'
}

// ── Storage ───────────────────────────────────────────────────────────────────

module storage 'modules/storage.bicep' = if (deployStorage) {
  name: 'storage'
  params: {
    location: location
    namePrefix: namePrefix
    privateEndpointSubnetId: peSubnetId
    privateDnsZoneResourceId: filePrivateDnsZoneId
    tags: tags
  }
}

// ── AVD Control Plane ─────────────────────────────────────────────────────────

module avd 'modules/avd-control-plane.bicep' = {
  name: 'avd-control-plane'
  params: {
    location: location
    namePrefix: namePrefix
    hostPoolType: hostPoolType
    maxSessionLimit: maxSessionLimit
    deployScalingPlan: deployScalingPlan
    scalingPlanTimeZone: scalingPlanTimeZone
    logAnalyticsWorkspaceId: logAnalyticsWorkspaceId
    tags: tags
  }
}

// ── Session Hosts ─────────────────────────────────────────────────────────────

module sessionHosts 'modules/session-hosts.bicep' = if (deploySessionHosts && deployKeyVault) {
  name: 'session-hosts'
  params: {
    location: location
    namePrefix: namePrefix
    sessionHostCount: sessionHostCount
    vmSize: vmSize
    subnetId: subnetId
    registrationToken: avd.outputs.registrationToken
    fslogixProfilePath: deployStorage ? storage.outputs.profileSharePath : ''
    adminUsername: adminUsername
    // Password is never in params — pulled directly from Key Vault at deploy time
    adminPassword: kv.getSecret('vm-admin-password')
    logAnalyticsWorkspaceId: logAnalyticsWorkspaceId
    tags: tags
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────────

output hostPoolId string = avd.outputs.hostPoolId
output workspaceId string = avd.outputs.workspaceId
output keyVaultName string = deployKeyVault ? kvModule.outputs.keyVaultName : ''
output storageAccountName string = deployStorage ? storage.outputs.storageAccountName : ''
output sessionHostNames array = (deploySessionHosts && deployKeyVault) ? sessionHosts.outputs.sessionHostNames : []
