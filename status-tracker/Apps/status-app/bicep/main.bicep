targetScope = 'resourceGroup'

@description('Environment name (dev/prod)')
param environment string

@description('Application name')
param appName string

@description('Location for resources')
param location string

@description('Azure Container Registry login server')
param acrLoginServer string

@description('Azure Container Registry username')
param acrUsername string

@description('Azure Container Registry password')
param acrPassword string

@description('Docker image name (repository:tag)')
param dockerImage string

@description('App Service Plan SKU')
@allowed([
  'B1'
  'B2'
  'B3'
  'P1v2'
  'P2v2'
])
param sku string = 'B1'

// Deploy App Service module
module appServiceModule './modules/appservice.bicep' = {
  name: '${appName}-appservice-module'
  params: {
    appName: appName
    environment: environment
    location: location
    sku: sku
    acrLoginServer: acrLoginServer
    acrUsername: acrUsername
    acrPassword: acrPassword
    dockerImage: dockerImage
  }
}
