targetScope = 'resourceGroup'

@allowed(['dev', 'prod'])
param environment string

param appName string
param location string
param acrName string
param vaultName string
param appServicePlanSku string = 'B1'
@secure()
param postgresPassword string
param dnsLabel string
param aciContainerGroupName string
param postgresImage string = 'postgres:15-alpine'
param postgresCpu int = 1
param postgresMemoryGb int = 1
param postgresDbName string = 'statusdb'
param postgresUser string = 'postgres'

module storage 'modules/storage.bicep' = {
  name: 'storage-deploy'
  params: {
    location: location
    environment: environment
  }
}

module aci 'modules/aci.bicep' = {
  name: 'aci-deploy'
  params: {
    location: location
    dnsLabel: dnsLabel
    postgresPassword: postgresPassword
    storageAccountName: storage.outputs.storageAccountName
    storageAccountKey: storage.outputs.storageAccountKey

    // Newly passed from dev.json
    containerGroupName: aciContainerGroupName
    postgresImage: postgresImage
    postgresCpu: postgresCpu
    postgresMemoryGb: postgresMemoryGb
    postgresDbName: postgresDbName
    postgresUser: postgresUser
  }
}

module web 'modules/appService.bicep' = {
  name: 'web-deploy'
  params: {
    location: location
    environment: environment
    appName: appName
    acrName: acrName
    vaultName: vaultName
    appServicePlanSku: appServicePlanSku
  }
}

output dbFqdn string = aci.outputs.dbFqdn
output storageAccountName string = storage.outputs.storageAccountName
output storageAccountKey string = storage.outputs.storageAccountKey
output appServiceName string = web.outputs.appServiceName
