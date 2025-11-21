targetScope = 'resourceGroup'

@description('Name of the Azure Container Registry')
param acrName string

@description('Location for ACR')
param location string

@description('SKU for ACR')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param acrSku string = 'Basic'

resource acr 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' = {
  name: acrName
  location: location
  sku: {
    name: acrSku
  }
  properties: {
    adminUserEnabled: true
  }
}

output acrLoginServer string = acr.properties.loginServer
output acrId string = acr.id
