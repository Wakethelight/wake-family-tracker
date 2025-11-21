targetScope = 'resourceGroup'

@description('App name')
param appName string

@description('Environment name')
param environment string

@description('Location for resources')
param location string

@description('App Service Plan SKU')
@allowed([
  'B1'
  'B2'
  'B3'
  'P1v2'
  'P2v2'
])
param sku string = 'B1'

@description('Azure Container Registry login server')
param acrLoginServer string

@description('Azure Container Registry username')
param acrUsername string

@description('Azure Container Registry password')
param acrPassword string

@description('Docker image name (repository:tag)')
param dockerImage string

// App Service Plan
resource appServicePlan 'Microsoft.Web/serverfarms@2022-03-01' = {
  name: 'asp-${appName}-${environment}'
  location: location
  sku: {
    name: sku
    tier: sku == 'B1' || sku == 'B2' || sku == 'B3' ? 'Basic' : 'PremiumV2'
    size: sku
    capacity: 1
  }
}

// App Service for Containers
resource appService 'Microsoft.Web/sites@2022-03-01' = {
  name: 'app-${appName}-${environment}'
  location: location
  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: {
      linuxFxVersion: 'DOCKER|${acrLoginServer}/${dockerImage}'
      appSettings: [
        {
          name: 'WEBSITES_ENABLE_APP_SERVICE_STORAGE'
          value: 'false'
        }
        {
          name: 'DOCKER_REGISTRY_SERVER_URL'
          value: 'https://${acrLoginServer}'
        }
        {
          name: 'DOCKER_REGISTRY_SERVER_USERNAME'
          value: acrUsername
        }
        {
          name: 'DOCKER_REGISTRY_SERVER_PASSWORD'
          value: acrPassword
        }
      ]
    }
    httpsOnly: true
  }
}

output appServiceName string = appService.name
output appServiceUrl string = appService.properties.defaultHostName
