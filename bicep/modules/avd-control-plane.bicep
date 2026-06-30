@description('Azure region')
param location string

@description('Name prefix for all AVD resources')
param namePrefix string

@description('Host pool type')
@allowed(['Pooled', 'Personal'])
param hostPoolType string = 'Pooled'

@description('Load balancing for Pooled pools')
@allowed(['BreadthFirst', 'DepthFirst'])
param loadBalancerType string = 'BreadthFirst'

@description('Maximum sessions per session host (Pooled only)')
param maxSessionLimit int = 10

@description('Deploy a weekday scaling plan')
param deployScalingPlan bool = true

@description('Time zone for the scaling plan')
param scalingPlanTimeZone string = 'GMT Standard Time'

@description('Log Analytics workspace resource ID for diagnostics')
param logAnalyticsWorkspaceId string = ''

param tags object = {}

// ── Host Pool ─────────────────────────────────────────────────────────────────

module hostPool 'br/public:avm/res/desktop-virtualization/host-pool:0.3.0' = {
  name: 'hostPool'
  params: {
    name: '${namePrefix}-hp'
    location: location
    tags: tags
    hostPoolType: hostPoolType
    loadBalancerType: loadBalancerType
    maxSessionLimit: maxSessionLimit
    preferredAppGroupType: 'Desktop'
    friendlyName: '${namePrefix} Host Pool'
    validationEnvironment: false
    diagnosticSettings: !empty(logAnalyticsWorkspaceId)
      ? [{ workspaceResourceId: logAnalyticsWorkspaceId }]
      : []
  }
}

// ── Application Group ─────────────────────────────────────────────────────────

module appGroup 'br/public:avm/res/desktop-virtualization/application-group:0.2.0' = {
  name: 'appGroup'
  params: {
    name: '${namePrefix}-dag'
    location: location
    tags: tags
    applicationGroupType: 'Desktop'
    hostpoolName: hostPool.outputs.name
    friendlyName: '${namePrefix} Desktop'
    diagnosticSettings: !empty(logAnalyticsWorkspaceId)
      ? [{ workspaceResourceId: logAnalyticsWorkspaceId }]
      : []
  }
}

// ── Workspace ─────────────────────────────────────────────────────────────────

module workspace 'br/public:avm/res/desktop-virtualization/workspace:0.3.0' = {
  name: 'workspace'
  params: {
    name: '${namePrefix}-ws'
    location: location
    tags: tags
    friendlyName: '${namePrefix} Workspace'
    applicationGroupReferences: [ appGroup.outputs.resourceId ]
    diagnosticSettings: !empty(logAnalyticsWorkspaceId)
      ? [{ workspaceResourceId: logAnalyticsWorkspaceId }]
      : []
  }
}

// ── Scaling Plan ──────────────────────────────────────────────────────────────

module scalingPlan 'br/public:avm/res/desktop-virtualization/scaling-plan:0.2.0' = if (deployScalingPlan && hostPoolType == 'Pooled') {
  name: 'scalingPlan'
  params: {
    name: '${namePrefix}-sp'
    location: location
    tags: tags
    timeZone: scalingPlanTimeZone
    hostPoolType: 'Pooled'
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
        rampUpStartTime: { hour: 7, minute: 0 }
        rampUpLoadBalancingAlgorithm: 'BreadthFirst'
        rampUpMinimumHostsPct: 20
        rampUpCapacityThresholdPct: 60
        peakStartTime: { hour: 9, minute: 0 }
        peakLoadBalancingAlgorithm: 'BreadthFirst'
        rampDownStartTime: { hour: 17, minute: 0 }
        rampDownLoadBalancingAlgorithm: 'DepthFirst'
        rampDownMinimumHostsPct: 10
        rampDownCapacityThresholdPct: 90
        rampDownWaitTimeMinutes: 30
        rampDownStopHostsWhen: 'ZeroActiveSessions'
        rampDownNotificationMessage: 'Your session will end in 30 minutes. Please save your work.'
        offPeakStartTime: { hour: 18, minute: 0 }
        offPeakLoadBalancingAlgorithm: 'DepthFirst'
      }
    ]
  }
}

// ── Registration token (used by session-hosts module) ─────────────────────────

param tokenExpiry string = dateTimeAdd(utcNow(), 'PT2H')

output hostPoolId string = hostPool.outputs.resourceId
output hostPoolName string = hostPool.outputs.name
output appGroupId string = appGroup.outputs.resourceId
output workspaceId string = workspace.outputs.resourceId
output registrationToken string = hostPool.outputs.?registrationToken ?? ''
output tokenExpiry string = tokenExpiry
