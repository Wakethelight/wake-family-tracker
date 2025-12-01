param location string
param environment string
param appName string
param acrName string
param vaultName string
param planSku string

resource plan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: '${appName}-plan'
  location: location
  sku: { name: planSku }
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
        { name: 'WEBSITE_CONTAINER_START_TIME_LIMIT', value: '300' }
        { name: 'WEBSITES_PORT', value: '8000' }
        { name: 'DB_CONNECTION_STRING', value: '@Microsoft.KeyVault(SecretUri=https://${vaultName}.vault.azure.net/secrets/db-connection-string)' }
      ]
    }
  }
  identity: { type: 'SystemAssigned' }
}

output appServiceName string = app.name
output principalId string = app.identity.principalId
