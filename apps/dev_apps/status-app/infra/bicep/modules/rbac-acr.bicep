targetScope = 'resourceGroup'

param acrName string
param principalId string

// Existing ACR within this scoped resource group
resource acr 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' existing = {
  name: acrName
}

// Role assignment: AcrPull
resource acrAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  // Deterministic name: same inputs always produce same GUID
  name: guid(acr.id, principalId, 'AcrPull')
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '7f951dda-4ed3-4680-a7ca-43fe172d538d' // AcrPull role definition ID
    )
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}

output acrResourceId string = acr.id
output assignedPrincipalId string = principalId
