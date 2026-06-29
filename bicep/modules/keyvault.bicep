@description('Azure region')
param location string

@description('Name prefix for Key Vault and identity resources')
param namePrefix string

@description('Secret name to store the VM admin password under')
param adminPasswordSecretName string = 'vm-admin-password'

@description('Object IDs of users/groups to grant Key Vault Secrets User (read) access')
param readerPrincipalIds array = []

param tags object = {}

// ── User-assigned managed identity (used by the deployment script) ────────────

resource deploymentIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${namePrefix}-id-kv-deploy'
  location: location
  tags: tags
}

// ── Key Vault ─────────────────────────────────────────────────────────────────

module keyVault 'br/public:avm/res/key-vault/vault:0.9.0' = {
  name: 'keyvault'
  params: {
    name: '${namePrefix}-kv'
    location: location
    tags: tags
    sku: 'standard'
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enablePurgeProtection: false   // set true for production
    roleAssignments: union(
      // deployment script identity needs Secrets Officer to create the password secret
      [
        {
          principalId: deploymentIdentity.properties.principalId
          roleDefinitionIdOrName: 'Key Vault Secrets Officer'
          principalType: 'ServicePrincipal'
        }
      ],
      // optional: grant read access to additional principals (e.g. the session host MSI)
      [for id in readerPrincipalIds: {
        principalId: id
        roleDefinitionIdOrName: 'Key Vault Secrets User'
        principalType: 'ServicePrincipal'
      }]
    )
  }
}

// ── Deployment script — generate password and store in Key Vault ──────────────
// Runs with AzureCLI. Idempotent: if the secret already exists it is left alone.

resource passwordScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: '${namePrefix}-gen-vm-password'
  location: location
  tags: tags
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${deploymentIdentity.id}': {} }
  }
  properties: {
    azCliVersion: '2.55.0'
    retentionInterval: 'PT1H'
    // Re-run only when Key Vault name changes (forceUpdateTag makes it idempotent otherwise)
    forceUpdateTag: keyVault.outputs.name
    environmentVariables: [
      { name: 'KV_NAME', value: keyVault.outputs.name }
      { name: 'SECRET_NAME', value: adminPasswordSecretName }
    ]
    scriptContent: '''
      set -euo pipefail
      existing=$(az keyvault secret show \
        --vault-name "$KV_NAME" \
        --name "$SECRET_NAME" \
        --query value -o tsv 2>/dev/null || true)
      if [ -z "$existing" ]; then
        # Generate: 32 random chars + enforce uppercase, digit, special char
        base=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 28)
        password="${base}Aa1!"
        az keyvault secret set \
          --vault-name "$KV_NAME" \
          --name "$SECRET_NAME" \
          --value "$password" \
          --output none
        echo "Password created in Key Vault"
      else
        echo "Password already exists — skipping generation"
      fi
      echo '{"status":"done"}' > "$AZ_SCRIPTS_OUTPUT_PATH"
    '''
  }
}

output keyVaultId string = keyVault.outputs.resourceId
output keyVaultName string = keyVault.outputs.name
output adminPasswordSecretName string = adminPasswordSecretName
