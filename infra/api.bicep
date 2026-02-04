@description('Environment name for resources')
param environmentName string

@description('Location for all resources')
param location string

@description('Tags for resources')
param tags object

@description('Container Apps Environment ID')
param containerAppsEnvironmentId string

@description('Container Registry Name')
param containerRegistryName string

@description('Storage Account Name')
param storageAccountName string

@description('Application Insights Name')
param appInsightsName string

@description('Container Registry Password')
@secure()
param registryPassword string

@description('Container image name')
param imageName string

// Reference existing resources
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: containerRegistryName
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: storageAccountName
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: appInsightsName
}

// Get storage connection string
var storageConnectionString = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'

// Container App for GPU Function with System-Assigned Managed Identity
resource containerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: 'ca-${environmentName}'
  location: location
  tags: union(tags, {
    'azd-service-name': 'api'
  })
  identity: {
    type: 'SystemAssigned'
  }
  kind: 'functionapp'
  properties: {
    managedEnvironmentId: containerAppsEnvironmentId
    workloadProfileName: 'gpu-profile'
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: 80
        transport: 'http'
        allowInsecure: false
      }
      registries: [
        {
          server: containerRegistry.properties.loginServer
          username: containerRegistry.listCredentials().username
          passwordSecretRef: 'acr-password'
        }
      ]
      secrets: [
        {
          name: 'acr-password'
          value: registryPassword
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'gpu-image-gen'
          image: imageName
          resources: {
            cpu: json('4')
            memory: '28Gi'
          }
          env: [
            {
              name: 'AzureWebJobsStorage'
              value: storageConnectionString
            }
            {
              name: 'FUNCTIONS_WORKER_RUNTIME'
              value: 'python'
            }
            {
              name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
              value: appInsights.properties.ConnectionString
            }
            {
              name: 'MODEL_ID'
              value: 'runwayml/stable-diffusion-v1-5'
            }
          ]
        }
      ]
      scale: {
        minReplicas: 0
        maxReplicas: 3
        rules: [
          {
            name: 'http-rule'
            http: {
              metadata: {
                concurrentRequests: '10'
              }
            }
          }
        ]
      }
    }
  }
}

// Outputs
output name string = containerApp.name
output uri string = 'https://${containerApp.properties.configuration.ingress.fqdn}'
output id string = containerApp.id
