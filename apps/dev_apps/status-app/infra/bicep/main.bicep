targetScope = 'resourceGroup'

@allowed(['dev', 'prod'])
param environment string
param location string
param app object
param postgres object
@secure()
param postgresPassword string


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
    dnsLabel: postgres.dnsLabel
    postgresPassword: postgresPassword
    storageAccountName: storage.outputs.storageAccountName
    storageAccountKey: storage.outputs.storageAccountKey

    // Newly passed from dev.json
    osType: postgres.osType
    containerGroupName: postgres.aciContainerGroupName
    postgresImage: postgres.postgresImage
    postgresCpu: postgres.postgresCpu
    postgresMemoryGb: postgres.postgresMemoryGb
    postgresDbName: postgres.postgresDbName
    postgresUser: postgres.postgresUser
  }
}

module web 'modules/appService.bicep' = {
  name: 'web-deploy'
  params: {
    location: location
    appName: app.name
    acrName: app.acrName
    vaultName: app.vaultName
    planSku: app.planSku
  }
}
module dbSecret 'modules/keyvault-secrets.bicep' = {
  name: 'db-connection-secret'
  scope: resourceGroup(app.vaultResourceGroup)
  params: {
    vaultName: app.vaultName
    secretName: 'db-connection-string'
    secretValue: 'postgresql://${postgres.adminUser}:${postgres.adminPassword}@${aci.outputs.dbFqdn}:5432/${postgres.dbName}?sslmode=enabled'
  }
}

//
// RBAC: assign Key Vault Secrets User at the vault’s RG
//
module kvRbac 'modules/rbac-keyvault.bicep' = {
  name: 'rbac-kv'
  scope: resourceGroup(app.vaultResourceGroup)
  params: {
    vaultName: app.vaultName
    principalId: web.outputs.principalId
  }
}

//
// RBAC: assign AcrPull at the ACR’s RG
//
module acrRbac 'modules/rbac-acr.bicep' = {
  name: 'rbac-acr'
  scope: resourceGroup(app.acrResourceGroup)
  params: {
    acrName: app.acrName
    principalId: web.outputs.principalId
  }
}

output dbFqdn string = aci.outputs.dbFqdn
output storageAccountName string = storage.outputs.storageAccountName
output storageAccountKey string = storage.outputs.storageAccountKey
output appServiceName string = web.outputs.appServiceName
output postgresUser string = postgres.postgresUser
output postgresDbName string = postgres.postgresDbName
