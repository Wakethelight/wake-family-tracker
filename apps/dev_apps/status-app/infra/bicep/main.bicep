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

module web 'modules/appService.bicep' = {
  name: 'web-deploy'
  params: {
    location: location
    appName: app.name
    acrLoginServer: app.acrLoginServer
    vaultName: app.vaultName
    planSku: app.planSku
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
    osType: postgres.osType
    containerGroupName: postgres.aciContainerGroupName
    postgresImage: postgres.postgresImage
    postgresCpu: postgres.postgresCpu
    postgresMemoryGb: postgres.postgresMemoryGb
    postgresDbName: postgres.postgresDbName
    postgresUser: postgres.postgresUser
  }
}

module dbSecret 'modules/keyvault-secrets.bicep' = {
  name: 'db-connection-secret'
  scope: resourceGroup(app.vaultResourceGroup)
  params: {
    vaultName: app.vaultName
    secretName: 'db-connection-string'
    secretValue: 'postgresql://${postgres.postgresUser}:${postgresPassword}@${aci.outputs.dbFqdn}:5432/${postgres.postgresDbName}?sslmode=enabled'
  }
}

// RBAC: Key Vault Secrets User for Web App
module kvRbac 'modules/rbac-keyvault.bicep' = {
  name: 'rbac-kv'
  scope: resourceGroup(app.vaultResourceGroup)
  params: {
    vaultName: app.vaultName
    principalId: web.outputs.principalId
  }
}

// RBAC: AcrPull for Web App
module acrRbacWeb 'modules/rbac-acr.bicep' = {
  name: 'rbac-acr-web'
  scope: resourceGroup(app.acrResourceGroup)
  params: {
    acrName: app.acrName
    principalId: web.outputs.principalId
  }
}

// RBAC: AcrPull for ACI
module acrRbacAci 'modules/rbac-acr.bicep' = {
  name: 'rbac-acr-aci'
  scope: resourceGroup(app.acrResourceGroup)
  params: {
    acrName: app.acrName
    principalId: aci.outputs.containerGroupPrincipalId
  }
}

output dbFqdn string = aci.outputs.dbFqdn
output storageAccountName string = storage.outputs.storageAccountName
output storageAccountKey string = storage.outputs.storageAccountKey
output appServiceName string = web.outputs.appServiceName
output postgresUser string = postgres.postgresUser
output postgresDbName string = postgres.postgresDbName
