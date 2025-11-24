targetScope = 'resourceGroup'  // Deploys to KV's RG

@description('Subscription ID')
param subscriptionId string = subscription().subscriptionId  // Default to current

@description('KV Resource Group Name')
param kvResourceGroupName string = 'rg-dev-kv-wake-dev'

@description('KV Name')
param keyVaultName string

@description('App Service Principal ID')
param principalId string

@roleDefinitionId('Microsoft.Authorization/roleDefinitions/4633458b-17de-408a-b874-0445c86b69e6')  // Key Vault Secrets User (built-in, no param needed)
@description('Grant app access to get secrets from KV')
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {  // Updated API version
  name: guid(subscriptionId, principalId, 'kv-secrets-user-${keyVaultName}')  // Deterministic GUID
  scope: resourceGroup(subscriptionId, kvResourceGroupName).getSecret(keyVaultName)  // Direct scope to KV (no 'existing' resource needed)
  properties: {
    principalId: principalId
    principalType: 'ServicePrincipal'
    description: 'Grant ${keyVaultName} access for db-connection-string (deployed ${deployment().name})'  // Now after var
  }
}

output roleAssignmentId string = roleAssignment.id
