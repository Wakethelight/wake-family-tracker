targetScope = 'resourceGroup'

param acrName string
param principalId string
param principalType string = 'ServicePrincipal'

// Existing ACR within this scoped resource group
resource acr 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' existing = {
  name: acrName
}

// Role assignment: AcrPull
resource acrAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, principalId, '7f951dda-4ed3-4680-a7ca-43fe172d538d')
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '7f951dda-4ed3-4680-a7ca-43fe172d538d' // AcrPull
    )
    principalId: principalId
    principalType: principalType
  }
}
