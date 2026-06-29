using './main.bicep'

// ── Identity ──────────────────────────────────────────────────────────────────
param namePrefix        = 'avd-prd'
param environment       = 'prd'

// ── Networking ────────────────────────────────────────────────────────────────
param deployNetworking            = true
param vnetAddressPrefix           = '10.20.0.0/16'
param sessionHostSubnetPrefix     = '10.20.1.0/24'
param privateEndpointSubnetPrefix = '10.20.2.0/24'

// ── Key Vault & credentials ───────────────────────────────────────────────────
param deployKeyVault          = true
param adminUsername           = 'avdadmin'
// Password is auto-generated and stored in Key Vault on first deploy — no value needed here
param kvReaderPrincipalIds    = []  // Add Entra group object IDs to grant read access

// ── Storage (FSLogix) ─────────────────────────────────────────────────────────
param deployStorage           = true
param filePrivateDnsZoneId    = ''  // Set to enable private endpoint for Azure Files

// ── AVD Control Plane ─────────────────────────────────────────────────────────
param hostPoolType            = 'Pooled'
param maxSessionLimit         = 10
param deployScalingPlan       = true
param scalingPlanTimeZone     = 'GMT Standard Time'

// ── Session Hosts ─────────────────────────────────────────────────────────────
param deploySessionHosts      = true
param sessionHostCount        = 2
param vmSize                  = 'Standard_D4s_v5'

// ── Monitoring ────────────────────────────────────────────────────────────────
param logAnalyticsWorkspaceId = ''  // Set to enable diagnostics and VM Insights
