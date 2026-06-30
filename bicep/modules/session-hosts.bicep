@description('Azure region')
param location string

@description('Name prefix for session host VMs (e.g. avd-prd — results in avd-prd-0, avd-prd-1...)')
param namePrefix string

@description('Number of session hosts to deploy')
@minValue(1)
@maxValue(50)
param sessionHostCount int = 2

@description('Index to start numbering from (use to add hosts without renaming existing ones)')
param sessionHostStartIndex int = 0

@description('VM size for session hosts')
param vmSize string = 'Standard_D4s_v5'

@description('Subnet resource ID session host NICs attach to')
param subnetId string

@description('AVD host pool registration token (from avd-control-plane module output)')
@secure()
param registrationToken string

@description('UNC path for FSLogix profiles (e.g. \\\\storage.file.core.windows.net\\fslogix-profiles)')
param fslogixProfilePath string

@description('Local admin username for session hosts')
param adminUsername string

@description('Local admin password for session hosts')
@secure()
param adminPassword string

@description('Entra tenant ID (used for AAD join)')
param tenantId string = tenant().tenantId

@description('Log Analytics workspace resource ID for VM insights')
param logAnalyticsWorkspaceId string = ''

param tags object = {}

// Windows 11 multi-session with Microsoft 365 Apps — standard AVD image
var imageReference = {
  publisher: 'MicrosoftWindowsDesktop'
  offer: 'office-365'
  sku: 'win11-23h2-avd-m365'
  version: 'latest'
}

// Inline setup script — downloads AVD agent and configures FSLogix
// Script is base64-encoded to avoid shell quoting issues
var setupScript = '''
param(
  [string]$RegistrationToken,
  [string]$FslogixProfilePath
)

$ErrorActionPreference = "Stop"
$logPath = "C:\\AVDSetup\\setup.log"
New-Item -ItemType Directory -Force -Path "C:\\AVDSetup" | Out-Null

function Write-Log { param($msg) Add-Content $logPath "$(Get-Date -f 'yyyy-MM-dd HH:mm:ss') $msg" }

Write-Log "Starting AVD session host setup"

# Install AVD Agent Boot Loader
Write-Log "Downloading AVD Boot Loader"
$bootLoaderMsi = "C:\\AVDSetup\\BootLoader.msi"
Invoke-WebRequest -Uri "https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrxrH" -OutFile $bootLoaderMsi -UseBasicParsing
Write-Log "Installing AVD Boot Loader"
Start-Process msiexec.exe -ArgumentList "/i `"$bootLoaderMsi`" /quiet /l*v C:\\AVDSetup\\BootLoader.log" -Wait -NoNewWindow

# Install AVD Agent
Write-Log "Downloading AVD Agent"
$agentMsi = "C:\\AVDSetup\\RDAgent.msi"
Invoke-WebRequest -Uri "https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrmXv" -OutFile $agentMsi -UseBasicParsing
Write-Log "Installing AVD Agent with registration token"
Start-Process msiexec.exe -ArgumentList "/i `"$agentMsi`" /quiet REGISTRATIONTOKEN=`"$RegistrationToken`" /l*v C:\\AVDSetup\\Agent.log" -Wait -NoNewWindow

# Configure FSLogix
Write-Log "Configuring FSLogix"
$regPath = "HKLM:\\SOFTWARE\\FSLogix\\Profiles"
New-Item -Path $regPath -Force | Out-Null
Set-ItemProperty -Path $regPath -Name "Enabled"      -Value 1 -Type DWord
Set-ItemProperty -Path $regPath -Name "VHDLocations" -Value $FslogixProfilePath -Type MultiString
Set-ItemProperty -Path $regPath -Name "SizeInMBs"    -Value 30720 -Type DWord
Set-ItemProperty -Path $regPath -Name "IsDynamic"    -Value 1 -Type DWord
Set-ItemProperty -Path $regPath -Name "DeleteLocalProfileWhenVHDShouldApply" -Value 1 -Type DWord

Write-Log "Setup complete"
'''

module sessionHosts 'br/public:avm/res/compute/virtual-machine:0.11.0' = [
  for i in range(sessionHostStartIndex, sessionHostCount): {
    name: 'vm-${namePrefix}-${i}'
    params: {
      name: '${namePrefix}-${i}'
      location: location
      tags: tags
      vmSize: vmSize
      zone: 0
      osType: 'Windows'
      imageReference: imageReference
      osDisk: {
        name: '${namePrefix}-${i}-osdisk'
        caching: 'ReadWrite'
        createOption: 'FromImage'
        deleteOption: 'Delete'
        diskSizeGB: 128
        managedDisk: { storageAccountType: 'Premium_LRS' }
      }
      adminUsername: adminUsername
      adminPassword: adminPassword
      nicConfigurations: [
        {
          name: '${namePrefix}-${i}-nic'
          deleteOption: 'Delete'
          ipConfigurations: [
            {
              name: 'ipconfig1'
              subnetResourceId: subnetId
              privateIPAllocationMethod: 'Dynamic'
            }
          ]
        }
      ]
      // Entra ID join (Entra-joined VMs)
      extensionAadJoinConfig: {
        enabled: true
      }
      // AVD agent + FSLogix via custom script extension
      extensionCustomScriptConfig: {
        enabled: true
        fileData: []
        tags: tags
        settings: {
          commandToExecute: 'powershell -ExecutionPolicy Bypass -Command "${setupScript}" -RegistrationToken "${registrationToken}" -FslogixProfilePath "${fslogixProfilePath}"'
        }
      }
      // VM Insights (optional — only if Log Analytics is configured)
      extensionMonitoringAgentConfig: !empty(logAnalyticsWorkspaceId)
        ? {
            enabled: true
            tags: tags
          }
        : { enabled: false }
    }
  }
]

output sessionHostNames array = [for i in range(sessionHostStartIndex, sessionHostCount): '${namePrefix}-${i}']
