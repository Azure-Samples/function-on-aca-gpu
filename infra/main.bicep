targetScope = 'subscription'

@description('Name of the environment which is used to generate a short unique hash used in all resources.')
@minLength(1)
@maxLength(64)
param environmentName string

@description('Primary location for all resources')
@allowed([
  'swedencentral'
  'westus3'
])
param location string = 'swedencentral'

param resourceGroupName string = ''

var abbrs = loadJsonContent('./abbreviations.json')
var tags = { 'azd-env-name': environmentName }

// Organize resources in a resource group
resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: !empty(resourceGroupName) ? resourceGroupName : '${abbrs.resourcesResourceGroups}${environmentName}'
  location: location
  tags: tags
}

// Container Apps hosting function app with GPU support
module containerApps './core/host/container-apps.bicep' = {
  name: 'container-apps'
  scope: rg
  params: {
    environmentName: environmentName
    location: location
    tags: tags
  }
}

// App outputs
output AZURE_LOCATION string = location
output AZURE_TENANT_ID string = tenant().tenantId
output AZURE_RESOURCE_GROUP string = rg.name
output AZURE_ENV_NAME string = environmentName

// Container Apps outputs
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = containerApps.outputs.registryLoginServer
output AZURE_CONTAINER_REGISTRY_NAME string = containerApps.outputs.registryName
output AZURE_CONTAINER_APPS_ENVIRONMENT_NAME string = containerApps.outputs.environmentName
output AZURE_CONTAINER_APPS_ENVIRONMENT_ID string = containerApps.outputs.environmentId
output AZURE_STORAGE_ACCOUNT_NAME string = containerApps.outputs.storageAccountName
output AZURE_APP_INSIGHTS_NAME string = containerApps.outputs.appInsightsName
output AZURE_STORAGE_CONNECTION_STRING string = containerApps.outputs.storageAccountConnectionString
#disable-next-line outputs-should-not-contain-secrets
output AZURE_CONTAINER_REGISTRY_PASSWORD string = containerApps.outputs.registryPassword
