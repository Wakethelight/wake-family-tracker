param location string = resourceGroup().location
param deployMode string = 'container' // 'container' or 'managed'
param acrName string
param appServicePlanName string
param webAppName string
param postgresName string = 'mypg'
param postgresAdmin string = 'pgadmin'
@secure()
param postgresPassword string

module plan './modules/appServicePlan.bicep' = {
  name: 'plan'
  params: {
    location: location
    appServicePlanName: appServicePlanName
  }
}

module webApp './modules/webAppContainer.bicep' = {
  name: 'webApp'
  params: {
    location: location
    acrName: acrName
    webAppName: webAppName
    appServicePlanId: plan.outputs.appServicePlanId
    vaultName: vaultName
  }
}

module postgresContainer './modules/postgresContainer.bicep' = if (deployMode == 'container') {
  name: 'postgresContainer'
  params: {
    location: location
    webAppName: webAppName
    acrName: acrName
  }
}

module postgresManaged './modules/postgresManaged.bicep' = if (deployMode == 'managed') {
  name: 'postgresManaged'
  params: {
    location: location
    postgresName: postgresName
    postgresAdmin: postgresAdmin
    postgresPassword: postgresPassword
  }
}

output webAppUrl string = webApp.outputs.webAppUrl
output dbConnectionString string = deployMode == 'container'
  ? postgresContainer.outputs.dbConnectionString
  : postgresManaged.outputs.dbConnectionString
