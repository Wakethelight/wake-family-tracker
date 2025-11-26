// This module is deployed at scope: resourceGroup(<vaultResourceGroup>)
targetScope = 'resourceGroup'

param vaultName string
param principalId string

// Existing vault within this scoped resource group
resource kv 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: vaultName
}

// Role assignment: Key Vault Secrets User
resource kvAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  // Deterministic name that doesn't depend on runtime-only values
  name: guid(kv.id, principalId, '4633458b-17de-408a-b874-0445c86b69e6')
  scope: kv
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '4633458b-17de-408a-b874-0445c86b69e6' // Key Vault Secrets User
    )
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}
