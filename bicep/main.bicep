// Verify latest AVM versions at:
// https://azure.github.io/Azure-Verified-Modules/indexes/bicep/bicep-resource-modules/

targetScope = 'resourceGroup'

@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Short name prefix used across all resource names (e.g. avd-prd)')
param namePrefix string

// ── Networking ────────────────────────────────────────────────────────────────

@description('Deploy a new VNet, or bring your own by setting deployNetworking to false and providing subnetId')
param deployNetworking bool = true

@description('VNet address space when deployNetworking is true')
param vnetAddressPrefix string = '10.20.0.0/16'

@description('Session host subnet prefix')
param sessionHostSubnetPrefix string = '10.20.1.0/24'

@description('Private endpoint subnet prefix')
param privateEndpointSubnetPrefix string = '10.20.2.0/24'

@description('Existing subnet resource ID (used when deployNetworking is false)')
param existingSubnetId string = ''

// ── Storage (FSLogix) ─────────────────────────────────────────────────────────

@description('Deploy Azure Files storage for FSLogix profiles')
param deployStorage bool = true

@description('Private DNS zone resource ID for file.core.windows.net (leave empty to skip private endpoint)')
param filePrivateDnsZoneId string = ''

// ── AVD Control Plane ─────────────────────────────────────────────────────────

@description('Pooled or Personal host pool')
@allowed(['Pooled', 'Personal'])
param hostPoolType string = 'Pooled'

@description('Maximum sessions per host (Pooled only)')
param maxSessionLimit int = 10

@description('Deploy auto-scaling plan (Pooled only)')
param deployScalingPlan bool = true

@description('Scaling plan time zone')
param scalingPlanTimeZone string = 'GMT Standard Time'

// ── Session Hosts ─────────────────────────────────────────────────────────────

@description('Deploy session host VMs')
param deploySessionHosts bool = true

@description('Number of session hosts to deploy')
param sessionHostCount int = 2

@description('VM size for session hosts')
param vmSize string = 'Standard_D4s_v5'

@description('Local admin username for session host VMs')
param adminUsername string

@secure()
@description('Local admin password for session host VMs')
param adminPassword string

// ── Monitoring ────────────────────────────────────────────────────────────────

@description('Log Analytics workspace resource ID — leave empty to skip diagnostics')
param logAnalyticsWorkspaceId string = ''

// ── Shared ────────────────────────────────────────────────────────────────────

@description('Environment tag (e.g. prd, dev)')
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

module sessionHosts 'modules/session-hosts.bicep' = if (deploySessionHosts) {
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
    adminPassword: adminPassword
    logAnalyticsWorkspaceId: logAnalyticsWorkspaceId
    tags: tags
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────────

output hostPoolId string = avd.outputs.hostPoolId
output workspaceId string = avd.outputs.workspaceId
output appGroupId string = avd.outputs.appGroupId
output storageAccountName string = deployStorage ? storage.outputs.storageAccountName : ''
output sessionHostNames array = deploySessionHosts ? sessionHosts.outputs.sessionHostNames : []
