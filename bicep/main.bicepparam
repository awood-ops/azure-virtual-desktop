using './main.bicep'

// ── Identity ──────────────────────────────────────────────────────────────────
param namePrefix         = 'avd-prd'
param environment        = 'prd'

// ── Networking ────────────────────────────────────────────────────────────────
param deployNetworking              = true
param vnetAddressPrefix             = '10.20.0.0/16'
param sessionHostSubnetPrefix       = '10.20.1.0/24'
param privateEndpointSubnetPrefix   = '10.20.2.0/24'
// param existingSubnetId           = '/subscriptions/.../subnets/snet-avd-hosts'  // when deployNetworking = false

// ── Storage (FSLogix) ─────────────────────────────────────────────────────────
param deployStorage          = true
param filePrivateDnsZoneId   = ''   // Set to private DNS zone resource ID to enable private endpoint

// ── AVD Control Plane ─────────────────────────────────────────────────────────
param hostPoolType           = 'Pooled'
param maxSessionLimit        = 10
param deployScalingPlan      = true
param scalingPlanTimeZone    = 'GMT Standard Time'

// ── Session Hosts ─────────────────────────────────────────────────────────────
param deploySessionHosts     = true
param sessionHostCount       = 2
param vmSize                 = 'Standard_D4s_v5'
param adminUsername          = 'avdadmin'
param adminPassword          = ''   // Set via pipeline secret or az cli --parameters adminPassword=...

// ── Monitoring ────────────────────────────────────────────────────────────────
param logAnalyticsWorkspaceId = ''  // Set to enable diagnostics and VM Insights
