targetScope = 'resourceGroup'

param vaultName string
param secretName string
@secure()
param secretValue string

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: vaultName
}

resource secret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: kv
  name: secretName
  properties: {
    value: secretValue
  }
}
output secretValue string = secret.properties.value
