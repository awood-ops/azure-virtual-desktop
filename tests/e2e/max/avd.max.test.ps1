#Requires -Modules Pester, Az.Accounts, Az.Resources, Az.Network, Az.KeyVault, Az.Storage, Az.DesktopVirtualization
<#
.SYNOPSIS
    Pester v5 post-deployment assertions for the AVD 'max' e2e scenario.
    Environment variables injected by the CI workflow:
      TEST_SUBSCRIPTION  — Azure subscription ID
      TEST_RG            — Resource group name (dep-avdNNNN-avd-max)
      TEST_NAME_PREFIX   — Module namePrefix used at deploy time (e.g. avdNNNNmax)
#>

BeforeAll {
    $script:sub        = $env:TEST_SUBSCRIPTION
    $script:rg         = $env:TEST_RG
    $script:namePrefix = $env:TEST_NAME_PREFIX   # e.g. avd5432max

    Set-AzContext -SubscriptionId $script:sub | Out-Null

    $p = $script:namePrefix
    $script:vnetName = "$p-vnet"
    $script:kvName   = "$p-kv"
    $script:hpName   = "$p-hp"
    $script:dagName  = "$p-dag"
    $script:wsName   = "$p-ws"
    $script:spName   = "$p-sp"
    $script:saName   = (($p + 'fslogix') -replace '-', '').ToLower()
    if ($script:saName.Length -gt 24) { $script:saName = $script:saName.Substring(0, 24) }

    $script:resourceGroup = Get-AzResourceGroup -Name $script:rg -ErrorAction SilentlyContinue
    $script:vnet          = Get-AzVirtualNetwork -Name $script:vnetName -ResourceGroupName $script:rg -ErrorAction SilentlyContinue
    $script:hostPool      = Get-AzWvdHostPool -Name $script:hpName -ResourceGroupName $script:rg -ErrorAction SilentlyContinue
    $script:appGroup      = Get-AzWvdApplicationGroup -Name $script:dagName -ResourceGroupName $script:rg -ErrorAction SilentlyContinue
    $script:workspace     = Get-AzWvdWorkspace -Name $script:wsName -ResourceGroupName $script:rg -ErrorAction SilentlyContinue
    $script:scalingPlan   = Get-AzWvdScalingPlan -Name $script:spName -ResourceGroupName $script:rg -ErrorAction SilentlyContinue
    $script:kv            = Get-AzKeyVault -VaultName $script:kvName -ResourceGroupName $script:rg -ErrorAction SilentlyContinue
    $script:sa            = Get-AzStorageAccount -Name $script:saName -ResourceGroupName $script:rg -ErrorAction SilentlyContinue
    $script:sessionHosts  = Get-AzWvdSessionHost -HostPoolName $script:hpName -ResourceGroupName $script:rg -ErrorAction SilentlyContinue
}

Describe 'Resource Group' {
    It 'Should exist' {
        $script:resourceGroup | Should -Not -BeNullOrEmpty
    }
}

Describe 'Networking' {
    It 'VNet <vnetName> should exist' -TestCases @{ vnetName = $script:vnetName } {
        $script:vnet | Should -Not -BeNullOrEmpty
    }
    It 'Session host subnet should exist' {
        $subnet = $script:vnet.Subnets | Where-Object Name -eq 'snet-avd-hosts'
        $subnet | Should -Not -BeNullOrEmpty
    }
    It 'NSG should be attached to session host subnet' {
        $subnet = $script:vnet.Subnets | Where-Object Name -eq 'snet-avd-hosts'
        $subnet.NetworkSecurityGroup | Should -Not -BeNullOrEmpty
    }
}

Describe 'Key Vault' {
    It '<kvName> should exist' -TestCases @{ kvName = $script:kvName } {
        $script:kv | Should -Not -BeNullOrEmpty
    }
    It 'vm-admin-password secret should be present' {
        $secret = Get-AzKeyVaultSecret -VaultName $script:kvName -Name 'vm-admin-password' -ErrorAction SilentlyContinue
        $secret | Should -Not -BeNullOrEmpty
    }
}

Describe 'Storage (FSLogix)' {
    It '<saName> should exist' -TestCases @{ saName = $script:saName } {
        $script:sa | Should -Not -BeNullOrEmpty
    }
    It 'Should be Premium_LRS SKU' {
        $script:sa.Sku.Name | Should -Be 'Premium_LRS'
    }
    It 'FSLogix profile share should exist' {
        $key    = (Get-AzStorageAccountKey -ResourceGroupName $script:rg -Name $script:saName)[0].Value
        $ctx    = New-AzStorageContext -StorageAccountName $script:saName -StorageAccountKey $key
        $shares = Get-AzStorageShare -Context $ctx -ErrorAction SilentlyContinue
        $shares.Count | Should -BeGreaterThan 0
    }
}

Describe 'AVD Control Plane' {
    It 'Host pool <hpName> should exist' -TestCases @{ hpName = $script:hpName } {
        $script:hostPool | Should -Not -BeNullOrEmpty
    }
    It 'Host pool should be Pooled type' {
        $script:hostPool.HostPoolType | Should -Be 'Pooled'
    }
    It 'Application group <dagName> should exist' -TestCases @{ dagName = $script:dagName } {
        $script:appGroup | Should -Not -BeNullOrEmpty
    }
    It 'Workspace <wsName> should exist' -TestCases @{ wsName = $script:wsName } {
        $script:workspace | Should -Not -BeNullOrEmpty
    }
    It 'Scaling plan <spName> should exist' -TestCases @{ spName = $script:spName } {
        $script:scalingPlan | Should -Not -BeNullOrEmpty
    }
}

Describe 'Session Hosts' {
    It 'At least 1 session host should be registered' {
        $script:sessionHosts.Count | Should -BeGreaterThan 0
    }
    It 'Expected 1 session host (sessionHostCount=1)' {
        $script:sessionHosts.Count | Should -Be 1
    }
    It 'No session hosts should be in an error state' {
        $unhealthy = $script:sessionHosts | Where-Object { $_.Status -notin 'Available', 'Disconnected', 'Upgrading' }
        $unhealthy | Should -BeNullOrEmpty
    }
}
