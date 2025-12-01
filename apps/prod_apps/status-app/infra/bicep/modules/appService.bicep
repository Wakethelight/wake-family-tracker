param location string
param environment string
param appName string
param planSku string
param acrLoginServer string
param subnetId string
param keyVaultName string

resource plan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: '${appName}-${environment}-plan'
  location: location
  sku: { name: planSku, tier: 'PremiumV3', capacity: 1 }
  properties: { reserved: true }
  tags: {
    environment: environment
  }
}

resource app 'Microsoft.Web/sites@2023-01-01' = {
  name: '${appName}-${environment}'
  location: location
  identity: { type: 'SystemAssigned' }
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    virtualNetworkSubnetId: subnetId
    siteConfig: {
      linuxFxVersion: 'DOCKER|${acrLoginServer}/status-app:latest'
      // Add app settings here if needed
      appSettings: [
        { name: 'WEBSITE_CONTAINER_START_TIME_LIMIT', value: '300' }
        { name: 'WEBSITES_PORT', value: '8000' }
        {name: 'DB_CONNECTION_STRING', value: '@Microsoft.KeyVault(SecretUri=https://${keyVaultName}.vault.azure.net/secrets/db-connection-string/)'}
      ]
    }
  }
  tags: {
    environment: environment
  }
}

output appServiceName string = app.name
output principalId string = app.identity.principalId
