using './main.bicep'

// ── Host Pool ─────────────────────────────────────────────────────────────────
param hostPoolName           = 'hp-avd-prd'
param hostPoolType           = 'Pooled'
param loadBalancerType       = 'BreadthFirst'
param maxSessionLimit        = 10
param hostPoolFriendlyName   = 'AVD Host Pool'
param preferredAppGroupType  = 'Desktop'

// ── Workspace ─────────────────────────────────────────────────────────────────
param workspaceName          = 'ws-avd-prd'
param workspaceFriendlyName  = 'AVD Workspace'

// ── Application Group ─────────────────────────────────────────────────────────
param appGroupName           = 'ag-avd-desktop-prd'

// ── Scaling Plan ──────────────────────────────────────────────────────────────
param deployScalingPlan      = false
param scalingPlanName        = 'sp-avd-prd'
param scalingPlanTimeZone    = 'GMT Standard Time'

// ── Shared ────────────────────────────────────────────────────────────────────
param environment            = 'prd'
