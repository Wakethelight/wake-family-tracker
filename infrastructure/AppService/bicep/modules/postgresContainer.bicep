param location string
param webAppName string
param acrName string

resource webApp 'Microsoft.Web/sites@2022-03-01' existing = {
  name: webAppName
}

resource config 'Microsoft.Web/sites/config@2022-03-01' = {
  name: 'web'
  parent: webApp
  properties: {
    linuxFxVersion: 'COMPOSE|docker-compose.yml'
    acrUseManagedIdentityCreds: true
  }
}

@description('Connection string for containerized Postgres (internal docker network)')
output dbConnectionString string = 'Host=db;Database=statusdb;User Id=postgres;Password=supersecret'
