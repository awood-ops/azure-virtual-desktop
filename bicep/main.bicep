// Verify latest AVM versions at:
// https://azure.github.io/Azure-Verified-Modules/indexes/bicep/bicep-resource-modules/

targetScope = 'resourceGroup'

@description('Azure region for all resources')
param location string = resourceGroup().location

// ── Host Pool ─────────────────────────────────────────────────────────────────

@description('Name of the AVD host pool')
param hostPoolName string

@description('Pooled (shared) or Personal (dedicated) host pool')
@allowed(['Pooled', 'Personal'])
param hostPoolType string = 'Pooled'

@description('Load balancing algorithm for Pooled pools')
@allowed(['BreadthFirst', 'DepthFirst'])
param loadBalancerType string = 'BreadthFirst'

@description('Maximum number of sessions per session host (Pooled only)')
param maxSessionLimit int = 10

@description('Friendly display name shown in the client')
param hostPoolFriendlyName string = ''

@description('Preferred app group type for session hosts')
@allowed(['Desktop', 'RailApplications'])
param preferredAppGroupType string = 'Desktop'

// ── Workspace ─────────────────────────────────────────────────────────────────

@description('Name of the AVD workspace')
param workspaceName string

@description('Friendly name for the workspace shown in the client')
param workspaceFriendlyName string = ''

// ── Application Group ─────────────────────────────────────────────────────────

@description('Name of the desktop application group')
param appGroupName string

// ── Scaling Plan ──────────────────────────────────────────────────────────────

@description('Deploy a scaling plan to auto-scale session hosts')
param deployScalingPlan bool = false

@description('Name of the scaling plan (required when deployScalingPlan is true)')
param scalingPlanName string = ''

@description('Time zone for the scaling plan schedule (e.g. GMT Standard Time)')
param scalingPlanTimeZone string = 'GMT Standard Time'

// ── Shared ────────────────────────────────────────────────────────────────────

@description('Environment tag (e.g. prd, dev)')
param environment string

param tags object = {
  environment: environment
  managedBy: 'bicep'
  repo: 'avd'
}

// ── Host Pool ─────────────────────────────────────────────────────────────────

module hostPool 'br/public:avm/res/desktop-virtualization/host-pool:0.3.0' = {
  name: 'hostPool'
  params: {
    name: hostPoolName
    location: location
    hostPoolType: hostPoolType
    loadBalancerType: loadBalancerType
    maxSessionLimit: maxSessionLimit
    friendlyName: empty(hostPoolFriendlyName) ? hostPoolName : hostPoolFriendlyName
    preferredAppGroupType: preferredAppGroupType
    tags: tags
  }
}

// ── Application Group ─────────────────────────────────────────────────────────

module appGroup 'br/public:avm/res/desktop-virtualization/application-group:0.2.0' = {
  name: 'appGroup'
  params: {
    name: appGroupName
    location: location
    applicationGroupType: 'Desktop'
    hostPoolResourceId: hostPool.outputs.resourceId
    tags: tags
  }
}

// ── Workspace ─────────────────────────────────────────────────────────────────

module workspace 'br/public:avm/res/desktop-virtualization/workspace:0.3.0' = {
  name: 'workspace'
  params: {
    name: workspaceName
    location: location
    friendlyName: empty(workspaceFriendlyName) ? workspaceName : workspaceFriendlyName
    appGroupResourceIds: [ appGroup.outputs.resourceId ]
    tags: tags
  }
}

// ── Scaling Plan (optional) ───────────────────────────────────────────────────

module scalingPlan 'br/public:avm/res/desktop-virtualization/scaling-plan:0.2.0' = if (deployScalingPlan) {
  name: 'scalingPlan'
  params: {
    name: scalingPlanName
    location: location
    timeZone: scalingPlanTimeZone
    hostPoolType: hostPoolType
    hostPoolReferences: [
      {
        hostPoolArmPath: hostPool.outputs.resourceId
        scalingPlanEnabled: true
      }
    ]
    schedules: [
      {
        name: 'Weekdays'
        daysOfWeek: [ 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday' ]
        peakStartTime: { hour: 8, minute: 0 }
        peakLoadBalancingAlgorithm: 'BreadthFirst'
        rampUpStartTime: { hour: 7, minute: 0 }
        rampUpLoadBalancingAlgorithm: 'BreadthFirst'
        rampUpMinimumHostsPct: 20
        rampUpCapacityThresholdPct: 60
        offPeakStartTime: { hour: 18, minute: 0 }
        offPeakLoadBalancingAlgorithm: 'DepthFirst'
        rampDownStartTime: { hour: 17, minute: 0 }
        rampDownLoadBalancingAlgorithm: 'DepthFirst'
        rampDownMinimumHostsPct: 10
        rampDownCapacityThresholdPct: 90
        rampDownWaitTimeMinutes: 30
        rampDownStopHostsWhen: 'ZeroActiveSessions'
        rampDownNotificationMessage: 'Your session will end in 30 minutes.'
      }
    ]
    tags: tags
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────────

output hostPoolId string = hostPool.outputs.resourceId
output hostPoolName string = hostPool.outputs.name
output appGroupId string = appGroup.outputs.resourceId
output workspaceId string = workspace.outputs.resourceId
