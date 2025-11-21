param location string
param postgresName string
param postgresAdmin string
@secure()
param postgresPassword string

resource postgres 'Microsoft.DBforPostgreSQL/flexibleServers@2022-12-01' = {
  name: postgresName
  location: location
  properties: {
    administratorLogin: postgresAdmin
    administratorLoginPassword: postgresPassword
    version: '15'
    storage: {
      storageSizeGB: 32
    }
  }
}

resource db 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2022-12-01' = {
  name: 'statusdb'
  parent: postgres
}

@description('Connection string for managed Postgres')
output dbConnectionString string = 'Server=${postgres.name}.postgres.database.azure.com;Database=statusdb;User Id=${postgresAdmin};Password=${postgresPassword};SslMode=Require'
