@description('Azure region')
param location string

@description('Name prefix for all storage resources')
param namePrefix string

@description('FSLogix profile share name')
param profileShareName string = 'fslogix-profiles'

@description('Subnet ID for the private endpoint')
param privateEndpointSubnetId string

@description('Private DNS zone resource ID for file.core.windows.net (must exist in the subscription)')
param privateDnsZoneResourceId string = ''

param tags object = {}

var storageAccountName = replace(toLower('${namePrefix}fslogix'), '-', '')

module storageAccount 'br/public:avm/res/storage/storage-account:0.14.0' = {
  name: 'storage-fslogix'
  params: {
    name: length(storageAccountName) > 24 ? substring(storageAccountName, 0, 24) : storageAccountName
    location: location
    tags: tags
    skuName: 'Premium_LRS'
    kind: 'FileStorage'
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
    }
    // Entra Kerberos auth for FSLogix — allows AAD-joined VMs to authenticate
    azureFilesIdentityBasedAuthentication: {
      directoryServiceOptions: 'AADKERB'
    }
    fileServices: {
      shares: [
        {
          name: profileShareName
          shareQuota: 1024  // GB — increase for larger environments
          accessTier: 'Premium'
        }
      ]
    }
    privateEndpoints: !empty(privateDnsZoneResourceId)
      ? [
          {
            subnetResourceId: privateEndpointSubnetId
            service: 'file'
            privateDnsZoneGroup: {
              privateDNSResourceIds: [ privateDnsZoneResourceId ]
            }
          }
        ]
      : []
  }
}

output storageAccountId string = storageAccount.outputs.resourceId
output storageAccountName string = storageAccount.outputs.name
output profileSharePath string = '\\\\${storageAccount.outputs.name}.file.core.windows.net\\${profileShareName}'
