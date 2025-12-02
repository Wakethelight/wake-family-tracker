param vaultName string
param secretName string
param fqdn string
param dbName string
param adminUser string
@secure()
param adminPassword string

var connectionString = 'postgresql://${adminUser}:${adminPassword}@${fqdn}:5432/${dbName}?sslmode=enabled'

resource secret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  name: '${vaultName}/${secretName}'
  properties: {
    value: connectionString
  }
}
