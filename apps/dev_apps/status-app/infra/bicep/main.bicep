targetScope = 'resourceGroup'

@allowed(['dev', 'prod'])
param environment string

param appName string
param location string
param acrName string
param vaultName string
param appServicePlanSku string
@secure()
param postgresPassword string
param dnsLabel string
param aciContainerGroupName string
param postgresImage string
param postgresCpu int
param postgresMemoryGb int
param postgresDbName string
param postgresUser string
param osType string

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
    osType: osType
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
output postgresUser string = postgresUser
output postgresDbName string = postgresDbName
