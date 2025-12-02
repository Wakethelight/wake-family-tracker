targetScope = 'resourceGroup'

param environment string
param location string
@secure()
param app object
param postgres object
param network object
param subscriptionId string

module net 'modules/network.bicep' = {
  name: 'network'
  params: {
    location: location
    name: network.vnetName
    addressPrefix: network.addressPrefix
    appSubnetPrefix: network.appSubnetPrefix
    peSubnetPrefix: network.peSubnetPrefix
    dnsZoneName: network.dnsZoneName
  }
}

resource kv 'Microsoft.KeyVault/vaults@2025-05-01' existing = {
  name: app.vaultName
  scope: resourceGroup(subscriptionId, app.vaultResourceGroup)
}

module db 'modules/postgres-flex.bicep' = {
  name: 'postgres'
  params: {
    location: location
    serverName: postgres.serverName
    dbName: postgres.dbName
    adminUser: postgres.adminUser
    adminPassword: kv.getSecret('postgres-admin-password')
    version: postgres.version
    tier: postgres.tier
    skuName: postgres.skuName
    storageSizeGB: postgres.storageSizeGB
    backupRetentionDays: postgres.backupRetentionDays
    highAvailability: postgres.highAvailability
    delegatedSubnetId: net.outputs.appSubnetId
    privateDnsZoneId: net.outputs.privateDnsZoneId
    serverParameters: postgres.serverParameters
    tenantId: postgres.tenantId
  }
}

module dbSecret 'modules/keyvault-secrets.bicep' = {
  name: 'db-connection-secret'
  scope: resourceGroup(app.vaultResourceGroup)
  params: {
    vaultName: app.vaultName
    secretName: 'db-connection-string'
    secretValue: 'postgresql://${postgres.adminUser}:${postgres.adminPassword}@${db.outputs.fqdn}:5432/${postgres.dbName}?sslmode=enabled'
  }
}

module web 'modules/appService.bicep' = {
  name: 'web'
  params: {
    environment: environment
    location: location
    appName: app.name
    planSku: app.planSku
    acrLoginServer: app.acrLoginServer
    subnetId: net.outputs.appSubnetId
    keyVaultName: app.vaultName
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
// RBAC: assign AcrPull at the ACR’s RGs
//
module acrRbac 'modules/rbac-acr.bicep' = {
  name: 'rbac-acr'
  scope: resourceGroup(app.acrResourceGroup)
  params: {
    acrName: app.acrName
    principalId: web.outputs.principalId
  }
}

output appServiceName string = web.outputs.appServiceName
output vaultName string = app.vaultName
output dbFqdn string = db.outputs.fqdn
output postgresUser string = postgres.adminUser
output postgresDbName string = postgres.dbName
