targetScope = 'resourceGroup'

@allowed(['dev', 'prod'])
param environment string
param location string
param app object
param postgres object
param acr object
param keyvault object
@secure()
param postgresPassword string
@secure()
param acrAdminPassword string

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
    acrLoginServer: acr.loginServer
    vaultName: keyvault.name
    planSku: app.planSku
  }
}

module aci 'modules/aci.bicep'= {
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
    acrAdminUsername: acr.adminUsername
    acrAdminPassword: acrAdminPassword
    acrName: acr.name
  }
}

module dbSecret 'modules/keyvault-secrets.bicep' = {
  name: 'db-connection-secret'
  scope: resourceGroup(keyvault.resourceGroup)
  params: {
    vaultName: keyvault.name
    secretName: 'db-connection-string'
    secretValue: 'postgresql://${postgres.postgresUser}:${postgresPassword}@${aci.outputs.dbFqdn}:5432/${postgres.postgresDbName}?sslmode=disabled'
  }
}

// RBAC: Key Vault Secrets User for Web App
module kvRbac 'modules/rbac-keyvault.bicep' = {
  name: 'rbac-kv'
  scope: resourceGroup(keyvault.resourceGroup)
  params: {
    vaultName: keyvault.name
    principalId: web.outputs.principalId
  }
}

// RBAC: AcrPull for Web App
module acrRbacWeb 'modules/rbac-acr.bicep' = {
  name: 'rbac-acr-web'
  scope: resourceGroup(acr.resourceGroup)
  params: {
    acrName: acr.name
    principalId: web.outputs.principalId
  }
}

// RBAC: AcrPull for ACI
module acrRbacAci 'modules/rbac-acr.bicep' = {
  name: 'rbac-acr-aci'
  scope: resourceGroup(acr.resourceGroup)
  params: {
    acrName: acr.name
    principalId: aci.outputs.containerGroupPrincipalId
  }
}

// Guarded outputs: emit empty string if module output is missing
output dbFqdn string = empty(aci.outputs.dbFqdn) ? '' : aci.outputs.dbFqdn
output storageAccountName string = empty(storage.outputs.storageAccountName) ? '' : storage.outputs.storageAccountName
output storageAccountKey string = empty(storage.outputs.storageAccountKey) ? '' : storage.outputs.storageAccountKey
output appServiceName string = empty(web.outputs.appServiceName) ? '' : web.outputs.appServiceName
output postgresUser string = empty(postgres.postgresUser) ? '' : postgres.postgresUser
output postgresDbName string = empty(postgres.postgresDbName) ? '' : postgres.postgresDbName

// Always safe: Web RBAC
output acrResourceIdForWeb string = empty(acrRbacWeb.outputs.acrResourceId) ? '' : acrRbacWeb.outputs.acrResourceId
output acrAssignedPrincipalWeb string = empty(acrRbacWeb.outputs.assignedPrincipalId) ? '' : acrRbacWeb.outputs.assignedPrincipalId

// Guarded: ACI RBAC
output acrResourceIdForAci string = empty(acrRbacAci.outputs.acrResourceId) ? '' : acrRbacAci.outputs.acrResourceId
output acrAssignedPrincipalAci string = empty(acrRbacAci.outputs.assignedPrincipalId) ? '' : acrRbacAci.outputs.assignedPrincipalId

