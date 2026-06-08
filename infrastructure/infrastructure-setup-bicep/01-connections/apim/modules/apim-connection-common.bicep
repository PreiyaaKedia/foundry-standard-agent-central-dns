/*
Common module for creating APIM connections to Azure AI Foundry projects.
This module handles the core connection logic and can be reused across different APIM connection samples.
*/

// Connection scope: 'project' (default) or 'account'
@allowed(['project', 'account'])
param connectionScope string = 'project'

// Project resource ID (required when scope = project)
param projectResourceId string = ''

// Account resource ID (required when scope = account)
param accountResourceId string = ''

param connectionName string

// APIM resource parameters
param apimResourceId string
param apiName string
param apimSubscriptionName string = 'master'

// Connection configuration
param authType string = 'ApiKey'
param isSharedToAll bool = false

// APIM-specific metadata (passed through from parent template)
param metadata object

// Resolve Foundry account/project names from the appropriate resource ID
var isAccountScope = connectionScope == 'account'
var sourceResourceId = isAccountScope ? accountResourceId : projectResourceId
var aiFoundryName = split(sourceResourceId, '/')[8]
var projectName = isAccountScope ? '' : split(projectResourceId, '/')[10]

// Extract APIM information from resource ID
var apimSubscriptionId = split(apimResourceId, '/')[2]
var apimResourceGroupName = split(apimResourceId, '/')[4]
var apimServiceName = split(apimResourceId, '/')[8]

// Reference the AI Foundry account
resource aiFoundry 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  name: aiFoundryName
  scope: resourceGroup()
}

// Reference the project within the AI Foundry account (only when scope = project)
resource aiProject 'Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview' existing = if (!isAccountScope) {
  name: empty(projectName) ? 'placeholder' : projectName
  parent: aiFoundry
}

// Reference the APIM service (can be in different resource group/subscription)
resource existingApim 'Microsoft.ApiManagement/service@2021-08-01' existing = {
  name: apimServiceName
  scope: resourceGroup(apimSubscriptionId, apimResourceGroupName)
}

// Reference the specific API within APIM
resource apimApi 'Microsoft.ApiManagement/service/apis@2021-08-01' existing = {
  name: apiName
  parent: existingApim
}

// Reference the APIM subscription to get keys (only for ApiKey auth)
resource apimSubscription 'Microsoft.ApiManagement/service/subscriptions@2021-08-01' existing = {
  name: apimSubscriptionName
  parent: existingApim
}

var connectionTarget = '${existingApim.properties.gatewayUrl}/${apimApi.properties.path}'

// ----------------------------------------
// PROJECT-LEVEL CONNECTIONS
// ----------------------------------------

resource connectionApiKeyProject 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' = if (!isAccountScope && authType == 'ApiKey') {
  name: connectionName
  parent: aiProject
  properties: {
    category: 'ApiManagement'
    target: connectionTarget
    authType: 'ApiKey'
    isSharedToAll: isSharedToAll
    credentials: {
      key: apimSubscription.listSecrets(apimSubscription.apiVersion).primaryKey
    }
    metadata: metadata
  }
}

resource connectionAADProject 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' = if (!isAccountScope && authType == 'ProjectManagedIdentity') {
  name: connectionName
  parent: aiProject
  properties: {
    category: 'ApiManagement'
    target: connectionTarget
    authType: 'ProjectManagedIdentity'
    audience: 'https://cognitiveservices.azure.com'
    isSharedToAll: isSharedToAll
    credentials: {}
    metadata: metadata
  }
}

// ----------------------------------------
// ACCOUNT-LEVEL CONNECTIONS
// Survives project deletion and is usable by every project in the account.
// ----------------------------------------

resource connectionApiKeyAccount 'Microsoft.CognitiveServices/accounts/connections@2025-04-01-preview' = if (isAccountScope && authType == 'ApiKey') {
  name: connectionName
  parent: aiFoundry
  properties: {
    category: 'ApiManagement'
    target: connectionTarget
    authType: 'ApiKey'
    isSharedToAll: true
    credentials: {
      key: apimSubscription.listSecrets(apimSubscription.apiVersion).primaryKey
    }
    metadata: metadata
  }
}

resource connectionAADAccount 'Microsoft.CognitiveServices/accounts/connections@2025-04-01-preview' = if (isAccountScope && authType == 'ProjectManagedIdentity') {
  name: connectionName
  parent: aiFoundry
  properties: {
    category: 'ApiManagement'
    target: connectionTarget
    authType: 'ProjectManagedIdentity'
    audience: 'https://cognitiveservices.azure.com'
    isSharedToAll: true
    credentials: {}
    metadata: metadata
  }
}

// Outputs (only from the created connection)
output connectionName string = connectionName
output connectionId string = isAccountScope
  ? (authType == 'ApiKey' ? connectionApiKeyAccount.id : connectionAADAccount.id)
  : (authType == 'ApiKey' ? connectionApiKeyProject.id : connectionAADProject.id)
output targetUrl string = connectionTarget
output authType string = authType
output connectionScope string = connectionScope
output metadata object = metadata
