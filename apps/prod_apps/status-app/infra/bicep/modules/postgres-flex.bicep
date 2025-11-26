targetScope = 'resourceGroup'

@description('Azure region')
param location string

@description('Server name (unique within resource group).')
param serverName string

@description('Database name to create after server provisioning.')
param dbName string

@description('Admin username (no @ symbol).')
param adminUser string

@secure()
@description('Admin password (secure).')
param adminPassword string

@description('Postgres version (e.g., 16, 15, 14).')
param version string

@description('Compute tier: Burstable, GeneralPurpose, MemoryOptimized.')
param tier string

@description('SKU name mapping to vCores (e.g., GP_Standard_D2s_v3).')
param skuName string

@description('Storage size in GB.')
param storageSizeGB int

@description('Backup retention in days (7–35).')
param backupRetentionDays int

@description('High availability mode: Disabled, ZoneRedundant.')
param highAvailability string

@description('Availability zone for single-zone deployments (e.g., 1, 2, 3).')
param zone string = '1'

@description('Delegated subnet resource ID for private networking.')
param delegatedSubnetId string

@description('Private DNS zone resource ID (privatelink.postgres.database.azure.com).')
param privateDnsZoneId string

@description('Optional server parameters to set (name/value pairs).')
param serverParameters array = [
  {
    name: 'pg_hint_plan.enable_hint'
    value: 'off'
  }
  {
    name: 'log_min_duration_statement'
    value: '1000'
  }
]

@description('Whether to require TLS on connections.')
param requireSsl bool

// Server
resource server 'Microsoft.DBforPostgreSQL/flexibleservers@2023-03-01-preview' = {
  name: serverName
  location: location
  sku: {
    name: skuName
    tier: tier
  }
  properties: {
    version: version
    administratorLogin: adminUser
    administratorLoginPassword: adminPassword
    storage: {
      storageSizeGB: storageSizeGB
      autoGrow: 'Enabled'
    }
    backup: {
      backupRetentionDays: backupRetentionDays
      geoRedundantBackup: highAvailability == 'ZoneRedundant' ? 'Enabled' : 'Disabled'
    }
    network: {
      delegatedSubnetResourceId: delegatedSubnetId
      privateDnsZoneArmResourceId: privateDnsZoneId
    }
    highAvailability: {
      mode: highAvailability
    }
    authConfig: {
      activeDirectoryAuth: 'Disabled'
      passwordAuth: 'Enabled'
    }
    createMode: 'Default'
    dataEncryption: {
      primaryKeyURI: '' // optionally use CMK later
      type: 'SystemManaged'
    }
    authConfig: {
      sslEnforcement: requireSsl ? 'Enabled' : 'Disabled'
    }
  }
  tags: {
    workload: 'status-app'
  }
}

// DB
resource database 'Microsoft.DBforPostgreSQL/flexibleservers/databases@2023-03-01-preview' = {
  parent: server
  name: dbName
  properties: {}
}

// Server parameters
resource paramSet 'Microsoft.DBforPostgreSQL/flexibleservers/configurations@2023-03-01-preview' = [for p in serverParameters: {
  parent: server
  name: p.name
  properties: {
    value: p.value
    source: 'user-override'
  }
}]

output fqdn string = server.properties.fullyQualifiedDomainName
output serverNameOut string = server.name
output dbNameOut string = dbName
