targetScope = 'subscription'  // Must be subscription scope for cross-RG role assignments

param keyVaultName string
param kvResourceGroupName string
param principalId string

// This is the only way that works reliably for shared KV in different RG
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(principalId, keyVaultName, 'secrets-user')
  scope: resourceGroup(kvResourceGroupName)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')  // Key Vault Secrets User
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}
