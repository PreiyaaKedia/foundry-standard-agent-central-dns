targetScope = 'resourceGroup'

@description('Foundry (Cognitive Services) account name')
param accountName string

@description('Existing project that already has the three BYO connections (source)')
param sourceProjectName string

@description('New project to receive cloned connections + capability host (target)')
param targetProjectName string

@description('Connection name on the source project pointing to Cosmos DB (thread storage)')
param cosmosDBConnection string

@description('Connection name on the source project pointing to Storage account (blob)')
param azureStorageConnection string

@description('Connection name on the source project pointing to AI Search (vector store)')
param aiSearchConnection string

@description('Target connection name for Cosmos DB on the new project. Must be unique within the account.')
param targetCosmosDBConnection string = '${cosmosDBConnection}-${targetProjectName}'

@description('Target connection name for Storage on the new project. Must be unique within the account.')
param targetAzureStorageConnection string = '${azureStorageConnection}-${targetProjectName}'

@description('Target connection name for AI Search on the new project. Must be unique within the account.')
param targetAiSearchConnection string = '${aiSearchConnection}-${targetProjectName}'

@description('Project capability host name')
param projectCapHost string = 'caphostproj'

@description('Resource ID of the Cosmos DB account (the underlying resource pointed to by the connection)')
param cosmosDBResourceId string

@description('Resource ID of the Storage account (the underlying resource pointed to by the connection)')
param azureStorageResourceId string

@description('Resource ID of the AI Search service (the underlying resource pointed to by the connection)')
param aiSearchResourceId string

// ----- parse name/rg/sub out of each resource ID at compile time -----
// Resource ID shape: /subscriptions/<sub>/resourceGroups/<rg>/providers/<...>/<name>
var cosmosIdParts  = split(cosmosDBResourceId,     '/')
var storageIdParts = split(azureStorageResourceId, '/')
var searchIdParts  = split(aiSearchResourceId,     '/')

var cosmosDBName              = last(cosmosIdParts)
var cosmosDBSubscriptionId    = cosmosIdParts[2]
var cosmosDBResourceGroupName = cosmosIdParts[4]

var azureStorageName              = last(storageIdParts)
var azureStorageSubscriptionId    = storageIdParts[2]
var azureStorageResourceGroupName = storageIdParts[4]

var aiSearchName              = last(searchIdParts)
var aiSearchSubscriptionId    = searchIdParts[2]
var aiSearchResourceGroupName = searchIdParts[4]

// ----- existing parents -----
resource account 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  name: accountName
}

resource sourceProject 'Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview' existing = {
  name: sourceProjectName
  parent: account
}

resource targetProject 'Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview' existing = {
  name: targetProjectName
  parent: account
}

// ----- read source connections -----
resource srcCosmos 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' existing = {
  name: cosmosDBConnection
  parent: sourceProject
}

resource srcStorage 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' existing = {
  name: azureStorageConnection
  parent: sourceProject
}

resource srcSearch 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' existing = {
  name: aiSearchConnection
  parent: sourceProject
}

// ----- clone onto target project (AAD auth, no credentials) -----
resource cloneCosmos 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' = {
  name: targetCosmosDBConnection
  parent: targetProject
  properties: {
    category: srcCosmos.properties.category
    target: srcCosmos.properties.target
    authType: srcCosmos.properties.authType
    isSharedToAll: srcCosmos.properties.isSharedToAll
    metadata: srcCosmos.properties.metadata
  }
}

resource cloneStorage 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' = {
  name: targetAzureStorageConnection
  parent: targetProject
  properties: {
    category: srcStorage.properties.category
    target: srcStorage.properties.target
    authType: srcStorage.properties.authType
    isSharedToAll: srcStorage.properties.isSharedToAll
    metadata: srcStorage.properties.metadata
  }
}

resource cloneSearch 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' = {
  name: targetAiSearchConnection
  parent: targetProject
  properties: {
    category: srcSearch.properties.category
    target: srcSearch.properties.target
    authType: srcSearch.properties.authType
    isSharedToAll: srcSearch.properties.isSharedToAll
    metadata: srcSearch.properties.metadata
  }
}

// ----- pre-capHost RBAC for the target project's managed identity -----
module storageAccountRoleAssignment 'azure-storage-account-role-assignment.bicep' = {
  name: 'storage-ra-${targetProjectName}'
  scope: resourceGroup(azureStorageSubscriptionId, azureStorageResourceGroupName)
  params: {
    azureStorageName: azureStorageName
    projectPrincipalId: targetProject.identity.principalId
  }
}

module cosmosAccountRoleAssignments 'cosmosdb-account-role-assignment.bicep' = {
  name: 'cosmos-ra-${targetProjectName}'
  scope: resourceGroup(cosmosDBSubscriptionId, cosmosDBResourceGroupName)
  params: {
    cosmosDBName: cosmosDBName
    projectPrincipalId: targetProject.identity.principalId
  }
}

module aiSearchRoleAssignments 'ai-search-role-assignments.bicep' = {
  name: 'search-ra-${targetProjectName}'
  scope: resourceGroup(aiSearchSubscriptionId, aiSearchResourceGroupName)
  params: {
    aiSearchName: aiSearchName
    projectPrincipalId: targetProject.identity.principalId
  }
}

// ----- format the project's internalId (32-char hex) into a dash-separated GUID -----
module formatProjectWorkspaceId 'format-project-workspace-id.bicep' = {
  name: 'fmt-wsid-${targetProjectName}'
  params: {
    // internalId exists at runtime but is missing from the published type schema.
    #disable-next-line BCP053
    projectWorkspaceId: targetProject.properties.internalId
  }
}

// ----- project capability host (delegated to existing module) -----
module capHost 'add-project-capability-host.bicep' = {
  name: 'caphost-${targetProjectName}'
  params: {
    accountName: accountName
    projectName: targetProjectName
    projectCapHost: projectCapHost
    cosmosDBConnection: targetCosmosDBConnection
    azureStorageConnection: targetAzureStorageConnection
    aiSearchConnection: targetAiSearchConnection
  }
  dependsOn: [
    cloneCosmos
    cloneStorage
    cloneSearch
    storageAccountRoleAssignment
    cosmosAccountRoleAssignments
    aiSearchRoleAssignments
  ]
}

// ----- post-capHost RBAC (ABAC-scoped, requires the project workspace ID) -----
module storageContainersRoleAssignment 'blob-storage-container-role-assignments.bicep' = {
  name: 'storage-containers-ra-${targetProjectName}'
  scope: resourceGroup(azureStorageSubscriptionId, azureStorageResourceGroupName)
  params: {
    storageName: azureStorageName
    aiProjectPrincipalId: targetProject.identity.principalId
    workspaceId: formatProjectWorkspaceId.outputs.projectWorkspaceIdGuid
  }
  dependsOn: [
    capHost
  ]
}

module cosmosContainerRoleAssignments 'cosmos-container-role-assignments.bicep' = {
  name: 'cosmos-containers-ra-${targetProjectName}'
  scope: resourceGroup(cosmosDBSubscriptionId, cosmosDBResourceGroupName)
  params: {
    cosmosAccountName: cosmosDBName
    projectWorkspaceId: formatProjectWorkspaceId.outputs.projectWorkspaceIdGuid
    projectPrincipalId: targetProject.identity.principalId
  }
  dependsOn: [
    capHost
    storageContainersRoleAssignment
  ]
}

output projectCapHostName string = capHost.outputs.projectCapHost
output clonedConnections array = [
  cloneCosmos.name
  cloneStorage.name
  cloneSearch.name
]
output targetProjectPrincipalId string = targetProject.identity.principalId
