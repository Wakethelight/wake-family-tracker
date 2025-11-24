targetScope = 'subscription'

param keyVaultName string
param kvResourceGroupName string
param principalId string

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  scope: resourceGroup(kvResourceGroupName)
  name: keyVaultName
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  parent: kv
  name: guid(principalId, keyVaultName, 'secrets-user')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}
