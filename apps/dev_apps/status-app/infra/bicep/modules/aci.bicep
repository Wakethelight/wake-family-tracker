param location string
param dnsLabel string
@secure()
param postgresPassword string
param storageAccountName string
@secure()
param storageAccountKey string

// These now come from dev.json
param containerGroupName string
param postgresImage string
param postgresCpu int
param postgresMemoryGb int
param postgresDbName string
param postgresUser string
param osType string

resource containerGroup 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: containerGroupName
  location: location
  properties: {
    osType: osType
    restartPolicy: 'Always'
    ipAddress: {
      type: 'Public'
      ports: [
        {
          port: 5432
          protocol: 'TCP'
        }
      ]
      dnsNameLabel: dnsLabel
    }
    containers: [
      {
        name: 'postgres'
        properties: {
          image: postgresImage
          resources: {
            requests: {
              cpu: postgresCpu
              memoryInGB: postgresMemoryGb
            }
          }
          ports: [
            {
              port: 5432
              protocol: 'TCP'
            }
          ]
          environmentVariables: [
            { name: 'POSTGRES_DB', value: postgresDbName }
            { name: 'POSTGRES_USER', value: postgresUser }
            { name: 'POSTGRES_PASSWORD', secureValue: postgresPassword }
          ]
          volumeMounts: [
            {
              name: 'initscript'
              mountPath: '/docker-entrypoint-initdb.d'
              readOnly: true
            }
          ]
        }
      }
    ]
    volumes: [
      {
        name: 'initscript'
        azureFile: {
          shareName: 'init-sql'
          storageAccountName: storageAccountName
          storageAccountKey: storageAccountKey
          readOnly: true
        }
      }
    ]
  }
}

output dbFqdn string = containerGroup.properties.ipAddress.fqdn
