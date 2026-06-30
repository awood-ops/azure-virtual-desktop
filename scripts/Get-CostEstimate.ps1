#Requires -Modules Az.Accounts, Az.Resources, Az.Compute, Az.Storage
<#
.SYNOPSIS
    Estimates monthly cost for an Azure Virtual Desktop resource group using
    the Azure Retail Prices API. Outputs a table to the console and saves
    CSV, JSON, and Markdown artifacts.

.PARAMETER ResourceGroupName
    Resource group to analyse.

.PARAMETER Location
    Azure region (ARM name, e.g. 'uksouth'). Used for pricing lookups.

.PARAMETER Currency
    ISO currency code (default GBP).

.PARAMETER OutputPath
    Directory to write cost-estimate.csv / .json / .md into.
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string] $ResourceGroupName,

    [string] $Location   = 'uksouth',
    [string] $Currency   = 'GBP',
    [string] $OutputPath = '.'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-RetailPrices {
    param([string] $Filter)
    $uri = 'https://prices.azure.com/api/retail/prices?api-version=2023-01-01-preview' +
           "&`$filter=$([Uri]::EscapeDataString($Filter))"
    try {
        $r = Invoke-RestMethod -Uri $uri -TimeoutSec 20
        return $r.Items | Where-Object priceType -eq 'Consumption'
    }
    catch {
        Write-Warning "Retail Prices API lookup failed: $_"
        return @()
    }
}

$estimates = [System.Collections.Generic.List[PSCustomObject]]::new()
$resources = Get-AzResource -ResourceGroupName $ResourceGroupName

foreach ($r in $resources) {
    Write-Verbose "Processing $($r.ResourceType): $($r.Name)"

    switch -Wildcard ($r.ResourceType.ToLower()) {

        'microsoft.compute/virtualmachines' {
            $vm   = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $r.Name
            $size = $vm.HardwareProfile.VmSize
            # API skuName: strip 'Standard_'/'Basic_', replace _ with space
            $sku  = $size -replace '^(Standard|Basic)_', '' -replace '_', ' '
            $prices = Get-RetailPrices -Filter (
                "armRegionName eq '$Location' and currencyCode eq '$Currency' " +
                "and serviceName eq 'Virtual Machines' and skuName eq '$sku'"
            )
            # Exclude Spot / Low Priority / Windows — want Linux pay-as-you-go
            $price = $prices |
                Where-Object { $_.meterName -notmatch 'Spot|Low Priority|Windows' } |
                Select-Object -First 1
            $monthly = if ($price) { [math]::Round($price.retailPrice * 730, 2) } else { 'N/A' }
            $estimates.Add([PSCustomObject]@{
                Resource     = $r.Name
                Type         = 'Virtual Machine'
                SKU          = $size
                UnitPrice    = if ($price) { "$Currency $($price.retailPrice)/hr" } else { 'lookup failed' }
                EstMonthly   = $monthly
                Notes        = '730 hrs/month (24/7 Linux PAYG)'
            })
        }

        'microsoft.storage/storageaccounts' {
            $sa = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $r.Name
            $prices = Get-RetailPrices -Filter (
                "armRegionName eq '$Location' and currencyCode eq '$Currency' " +
                "and serviceName eq 'Storage' and productName eq 'Premium Files' " +
                "and meterName eq 'LRS Capacity'"
            )
            $price = $prices | Select-Object -First 1
            $estimates.Add([PSCustomObject]@{
                Resource   = $r.Name
                Type       = 'Storage Account (Premium Files)'
                SKU        = $sa.Sku.Name
                UnitPrice  = if ($price) { "$Currency $($price.retailPrice)/GB/mo" } else { 'lookup failed' }
                EstMonthly = 'Usage-dependent'
                Notes      = 'FSLogix profiles — scales with profile data size'
            })
        }

        'microsoft.keyvault/vaults' {
            $prices = Get-RetailPrices -Filter (
                "armRegionName eq '$Location' and currencyCode eq '$Currency' " +
                "and serviceName eq 'Key Vault' and meterName eq 'Operations'"
            )
            $price = $prices | Select-Object -First 1
            $estimates.Add([PSCustomObject]@{
                Resource   = $r.Name
                Type       = 'Key Vault'
                SKU        = 'Standard'
                UnitPrice  = if ($price) { "$Currency $($price.retailPrice)/10k ops" } else { 'lookup failed' }
                EstMonthly = 'Usage-dependent'
                Notes      = 'Typically < 1 GBP/month for AVD workloads'
            })
        }

        'microsoft.desktopvirtualization/*' {
            $estimates.Add([PSCustomObject]@{
                Resource   = $r.Name
                Type       = $r.ResourceType.Split('/')[-1]
                SKU        = 'N/A'
                UnitPrice  = 'Free'
                EstMonthly = 0
                Notes      = 'AVD control plane — no charge'
            })
        }

        'microsoft.network/virtualnetworks' {
            $estimates.Add([PSCustomObject]@{
                Resource   = $r.Name
                Type       = 'Virtual Network'
                SKU        = 'N/A'
                UnitPrice  = 'Free + egress'
                EstMonthly = 'Usage-dependent'
                Notes      = 'VNet free; outbound data transfer charged per GB'
            })
        }

        'microsoft.network/networksecuritygroups' {
            $estimates.Add([PSCustomObject]@{
                Resource   = $r.Name
                Type       = 'Network Security Group'
                SKU        = 'N/A'
                UnitPrice  = 'Free'
                EstMonthly = 0
                Notes      = 'NSGs are free'
            })
        }
    }
}

# ── Console output ────────────────────────────────────────────────────────────

Write-Host "`n=== Cost Estimate: $ResourceGroupName ===" -ForegroundColor Cyan
Write-Host "Region: $Location  |  Currency: $Currency  |  VM hours: 730/month (24/7 PAYG)`n" -ForegroundColor Gray

if ($estimates.Count -eq 0) {
    Write-Warning 'No priceable resources found.'
}
else {
    $estimates | Format-Table Resource, Type, SKU, UnitPrice, EstMonthly, Notes -AutoSize
}

$numericTotal = ($estimates |
    Where-Object { $_.EstMonthly -is [double] -or $_.EstMonthly -is [int] } |
    Measure-Object -Property EstMonthly -Sum).Sum

Write-Host "Compute subtotal (24/7): $Currency $([math]::Round($numericTotal, 2))/month" -ForegroundColor Green
Write-Host "Storage, Key Vault, and network egress costs depend on actual usage.`n"

# ── Artifacts ─────────────────────────────────────────────────────────────────

$null = New-Item -ItemType Directory -Force -Path $OutputPath

$estimates | Export-Csv  -Path "$OutputPath/cost-estimate.csv" -NoTypeInformation -Force
$estimates | ConvertTo-Json -Depth 3 | Out-File -FilePath "$OutputPath/cost-estimate.json" -Force

# Markdown — also written to $GITHUB_STEP_SUMMARY if running in Actions
$rows = $estimates | ForEach-Object {
    "| $($_.Resource) | $($_.Type) | $($_.SKU) | $($_.UnitPrice) | $($_.EstMonthly) | $($_.Notes) |"
}
$md = @"
## Cost Estimate — $ResourceGroupName

> **Region:** \`$Location\` &nbsp;|&nbsp; **Currency:** \`$Currency\` &nbsp;|&nbsp; **VM assumption:** 730 hrs/month (24/7 PAYG Linux)

| Resource | Type | SKU | Unit Price | Est. Monthly | Notes |
|---|---|---|---|---|---|
$($rows -join "`n")

**Compute subtotal (24/7 runtime):** $Currency $([math]::Round($numericTotal, 2))/month

> Storage and Key Vault costs are usage-dependent and excluded from the subtotal.
> Cost Management actual charges appear within 24–48 hours of resource creation.
"@

$md | Out-File -FilePath "$OutputPath/cost-estimate.md" -Force

if ($env:GITHUB_STEP_SUMMARY) {
    Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value $md
}

Write-Host "Artifacts saved to: $OutputPath (csv / json / md)"
