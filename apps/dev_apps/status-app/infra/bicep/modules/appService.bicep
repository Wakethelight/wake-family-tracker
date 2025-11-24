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
      ]
    }
  }
  identity: { type: 'SystemAssigned' }
}

output appServiceName string = app.name
