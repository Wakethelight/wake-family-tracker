param location string
param environment string
param appName string
param acrName string
param vaultName string
param appServicePlanSku string

resource plan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: '${appName}-plan'
  location: location
  sku: { name: appServicePlanSku }
  properties: { reserved: true }
}

resource app 'Microsoft.Web/sites@2023-12-01' = {
  name: '${appName}-${environment}'
  location: location
  properties: {
    serverFarmId: plan.id
    siteConfig: {
      linuxFxVersion: 'DOCKER|${acrName}.azurecr.io/status-app:latest'
      appSettings: [
        { name: 'WEBSITES_PORT', value: '8000' }
        { name: 'KEY_VAULT_URL', value: 'https://${vaultName}.vault.azure.net/' }
        { name: 'WEBSITE_SITE_NAME', value: '${appName}-${environment}' }
      ]
    }
  }
  identity: { type: 'SystemAssigned' }
}

// Grant App Service identity Get access to KV
resource kvAccess 'Microsoft.KeyVault/vaults/accessPolicies@2023-07-01' = {
  name: '${vaultName}/add'
  properties: {
    accessPolicies: [
      {
        tenantId: subscription().tenantId
        objectId: app.identity.principalId
        permissions: { secrets: ['get'] }
      }
    ]
  }
}

output appServiceName string = app.name
