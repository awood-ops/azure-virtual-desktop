#Requires -Modules Az.Accounts, Az.Resources, Az.Network, Az.KeyVault, Az.Storage, Az.DesktopVirtualization
<#
.SYNOPSIS
    Validates that an Azure Virtual Desktop deployment is correctly provisioned.

.DESCRIPTION
    Checks that all resources created by the AVD Bicep deployment exist and are in a healthy state:
      - Resource group
      - Virtual network and subnets
      - Network security group
      - Key Vault and VM admin password secret
      - Storage account (FSLogix)
      - AVD host pool
      - AVD application group
      - AVD workspace
      - AVD scaling plan (if deployed)
      - Session hosts — registered and available

    Exits with code 1 if any check fails — suitable for use in CI pipelines.

.PARAMETER SubscriptionId
    Azure subscription ID containing the AVD resources.

.PARAMETER ResourceGroupName
    Resource group containing the AVD resources.

.PARAMETER NamePrefix
    Name prefix used during deployment (e.g. 'avd-prd'). Used to derive default resource names.

.PARAMETER HostPoolName
    Override the host pool name. Default: hp-<NamePrefix>

.PARAMETER AppGroupName
    Override the application group name. Default: ag-desktop-<NamePrefix>

.PARAMETER WorkspaceName
    Override the workspace name. Default: ws-<NamePrefix>

.PARAMETER KeyVaultName
    Override the Key Vault name (derived from deployment — check outputs if unsure).

.PARAMETER StorageAccountName
    Override the storage account name.

.PARAMETER VnetName
    Override the VNet name. Default: vnet-<NamePrefix>

.PARAMETER ExpectedSessionHostCount
    Expected number of registered session hosts. Default: 0 (skip count check).

.EXAMPLE
    .\Test-AvdDeployment.ps1 -SubscriptionId '00000000-...' -ResourceGroupName 'rg-avd-prd' -NamePrefix 'avd-prd'

.EXAMPLE
    .\Test-AvdDeployment.ps1 -SubscriptionId '00000000-...' -ResourceGroupName 'rg-avd-prd' -NamePrefix 'avd-prd' -ExpectedSessionHostCount 2 -Verbose
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string] $SubscriptionId,

    [Parameter(Mandatory)]
    [string] $ResourceGroupName,

    [Parameter(Mandatory)]
    [string] $NamePrefix,

    [string] $HostPoolName             = '',
    [string] $AppGroupName             = '',
    [string] $WorkspaceName            = '',
    [string] $KeyVaultName             = '',
    [string] $StorageAccountName       = '',
    [string] $VnetName                 = '',
    [int]    $ExpectedSessionHostCount = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Get-AzContext)) {
    throw 'No Azure context found. Run Connect-AzAccount before invoking this script.'
}

Set-AzContext -SubscriptionId $SubscriptionId | Out-Null

# Apply naming defaults
if (-not $HostPoolName)       { $HostPoolName       = "hp-$NamePrefix" }
if (-not $AppGroupName)        { $AppGroupName       = "ag-desktop-$NamePrefix" }
if (-not $WorkspaceName)       { $WorkspaceName      = "ws-$NamePrefix" }
if (-not $VnetName)            { $VnetName           = "vnet-$NamePrefix" }

$results = @()
$check = { param($name, $pass, $detail)
    [PSCustomObject]@{ Check = $name; Status = if ($pass) { 'PASS' } else { 'FAIL' }; Detail = $detail }
}

# ── Resource group ────────────────────────────────────────────────────────────
$rg = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
$results += & $check "Resource group '$ResourceGroupName' exists" ($null -ne $rg) ($rg ? $rg.Location : 'NOT FOUND')

# ── Networking ────────────────────────────────────────────────────────────────
$vnet = Get-AzVirtualNetwork -Name $VnetName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
$results += & $check "VNet '$VnetName' exists" ($null -ne $vnet) ($vnet ? "Address: $($vnet.AddressSpace.AddressPrefixes -join ', ')" : 'NOT FOUND')

if ($vnet) {
    $sessionHostSubnet = $vnet.Subnets | Where-Object { $_.Name -like '*session*' -or $_.Name -like '*host*' }
    $results += & $check "Session host subnet exists" ($null -ne $sessionHostSubnet) ($sessionHostSubnet ? $sessionHostSubnet.Name : 'NOT FOUND')

    if ($sessionHostSubnet) {
        $nsgAssoc = $null -ne $sessionHostSubnet.NetworkSecurityGroup
        $results += & $check "NSG attached to session host subnet" $nsgAssoc ($nsgAssoc ? $sessionHostSubnet.NetworkSecurityGroup.Id.Split('/')[-1] : 'NO NSG ATTACHED')
    }
}

# ── Key Vault ─────────────────────────────────────────────────────────────────
if ($KeyVaultName) {
    $kv = Get-AzKeyVault -VaultName $KeyVaultName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
    $results += & $check "Key Vault '$KeyVaultName' exists" ($null -ne $kv) ($kv ? "URI: $($kv.VaultUri)" : 'NOT FOUND')

    if ($kv) {
        try {
            $secret = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name 'vm-admin-password' -ErrorAction Stop
            $results += & $check "Secret 'vm-admin-password' exists in Key Vault" $true "Created: $($secret.Created?.ToString('yyyy-MM-dd') ?? 'unknown')"
        } catch {
            $results += & $check "Secret 'vm-admin-password' exists in Key Vault" $false 'NOT FOUND or no access'
        }
    }
} else {
    # Try to find KV in the resource group
    $kvs = Get-AzKeyVault -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
    $results += & $check "Key Vault exists in resource group" ($kvs.Count -gt 0) ($kvs.Count -gt 0 ? ($kvs | Select-Object -ExpandProperty VaultName) -join ', ' : 'NONE FOUND — pass -KeyVaultName to check secret')
}

# ── Storage (FSLogix) ─────────────────────────────────────────────────────────
if ($StorageAccountName) {
    $sa = Get-AzStorageAccount -Name $StorageAccountName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
    $results += & $check "Storage account '$StorageAccountName' exists" ($null -ne $sa) ($sa ? "SKU: $($sa.Sku.Name)  Kind: $($sa.Kind)" : 'NOT FOUND')
    if ($sa) {
        $results += & $check "Storage account is Premium (FSLogix)" ($sa.Sku.Tier -eq 'Premium') $sa.Sku.Tier
        $share = Get-AzStorageShare -Context $sa.Context -ErrorAction SilentlyContinue | Select-Object -First 1
        $results += & $check "File share exists (FSLogix profiles)" ($null -ne $share) ($share ? $share.Name : 'NO SHARE FOUND')
    }
} else {
    $sas = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
    $results += & $check "Storage account exists in resource group" ($sas.Count -gt 0) ($sas.Count -gt 0 ? ($sas | Select-Object -ExpandProperty StorageAccountName) -join ', ' : 'NONE FOUND — pass -StorageAccountName to check FSLogix share')
}

# ── AVD control plane ─────────────────────────────────────────────────────────
$hostPool = Get-AzWvdHostPool -Name $HostPoolName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
$results += & $check "Host pool '$HostPoolName' exists" ($null -ne $hostPool) ($hostPool ? "Type: $($hostPool.HostPoolType)  LoadBalancer: $($hostPool.LoadBalancerType)" : 'NOT FOUND')

if ($hostPool) {
    $results += & $check "Host pool registration token status" ($hostPool.RegistrationInfo -ne $null) ($hostPool.RegistrationInfo ? 'Registration info present' : 'No registration info')
}

$appGroup = Get-AzWvdApplicationGroup -Name $AppGroupName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
$results += & $check "Application group '$AppGroupName' exists" ($null -ne $appGroup) ($appGroup ? "Kind: $($appGroup.ApplicationGroupType)" : 'NOT FOUND')

$workspace = Get-AzWvdWorkspace -Name $WorkspaceName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
$results += & $check "Workspace '$WorkspaceName' exists" ($null -ne $workspace) ($workspace ? "ID: $($workspace.Id.Split('/')[-1])" : 'NOT FOUND')

# ── Session hosts ─────────────────────────────────────────────────────────────
if ($hostPool) {
    $sessionHosts = Get-AzWvdSessionHost -HostPoolName $HostPoolName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
    $available    = $sessionHosts | Where-Object { $_.Status -eq 'Available' }
    $results += & $check "Session hosts registered" ($sessionHosts.Count -gt 0) "$($sessionHosts.Count) registered  $($available.Count) available"

    if ($ExpectedSessionHostCount -gt 0) {
        $results += & $check "Session host count matches expected ($ExpectedSessionHostCount)" ($sessionHosts.Count -eq $ExpectedSessionHostCount) "Found: $($sessionHosts.Count)"
    }

    $unhealthy = $sessionHosts | Where-Object { $_.Status -notin 'Available','Disconnected' }
    $results += & $check "No unhealthy session hosts" ($unhealthy.Count -eq 0) ($unhealthy.Count -gt 0 ? "$($unhealthy.Count) in unexpected state" : 'Clean')
}

# ── Scaling plan ──────────────────────────────────────────────────────────────
$scalingPlan = Get-AzWvdScalingPlan -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue | Select-Object -First 1
$results += & $check "Scaling plan exists" ($null -ne $scalingPlan) ($scalingPlan ? $scalingPlan.Name : 'NOT FOUND (optional — only if deployScalingPlan=true)')

# ── Output ────────────────────────────────────────────────────────────────────
Write-Host "`n=== AVD Deployment Validation: $ResourceGroupName ===" -ForegroundColor Cyan
$results | Format-Table -AutoSize

$pass = ($results | Where-Object Status -eq 'PASS').Count
$fail = ($results | Where-Object Status -eq 'FAIL').Count
Write-Host "Results — Pass: $pass  Fail: $fail  Total: $($results.Count)" -ForegroundColor ($fail -gt 0 ? 'Red' : 'Green')

if ($fail -gt 0) { exit 1 }
