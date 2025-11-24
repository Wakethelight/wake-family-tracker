targetScope = 'resourceGroup'  // Deploys into the KV's RG

@description('Name of the Key Vault')
param keyVaultName string

@description('Resource group name of the Key Vault')
param kvResourceGroupName string = 'rg-dev-kv-wake-dev'  // Hardcode or param for flexibility

@description('Principal ID of the App Service managed identity')
param principalId string

@description('Role definition ID for Key Vault Secrets User (get secrets only)')
param roleDefinitionId string = '4633458b-17de-408a-b874-0445c86b69e6'

@description('Unique description for the role assignment')
param description string = 'App Service access to KV secrets'

var roleAssignmentName = guid(resourceGroup().id, principalId, 'kv-secrets-user')  // Deterministic GUID for repeatability

// Reference the existing KV in its RG
resource existingKv 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
  scope: resourceGroup(subscription().subscriptionId, kvResourceGroupName)  // Cross-RG reference
}

// Create the role assignment scoped to the KV (vault-level, not secret-specific for simplicity)
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2023-04-01' = {
  name: roleAssignmentName
  scope: existingKv
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
    principalId: principalId
    principalType: 'ServicePrincipal'  // For managed identities
    description: description
  }
}

output roleAssignmentId string = roleAssignment.id
