param location string
param acrName string
param webAppName string
param appServicePlanId string
param vaultName string

resource webApp 'Microsoft.Web/sites@2022-03-01' = {
  name: webAppName
  location: location
  properties: {
    serverFarmId: appServicePlanId
    siteConfig: {
      linuxFxVersion: 'DOCKER|${acrName}.azurecr.io/statusapp:latest'
      acrUseManagedIdentityCreds: true
      appSettings: [
        {
          name: 'DB_CONNECTION_STRING'
          value: '@Microsoft.KeyVault(SecretUri=https://${vaultName}.vault.azure.net/secrets/dbConnectionString)'
        },        {
          name: 'ACR_LOGIN_SERVER'
          value: '@Microsoft.KeyVault(SecretUri=https://${vaultName}.vault.azure.net/secrets/acrLoginServer)'
        }
      ]
    }
  }
}

output webAppUrl string = 'https://${webApp.properties.defaultHostName}'
