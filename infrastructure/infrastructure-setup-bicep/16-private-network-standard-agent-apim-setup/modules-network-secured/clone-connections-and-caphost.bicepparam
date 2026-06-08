using './clone-connections-and-caphost.bicep'

// --- Foundry account + projects ---
param accountName        = 'aiservicesgrdc'
param sourceProjectName  = 'projectgrdc'
param targetProjectName  = 'projectapimtest'

// --- Source connections on projectgrdc ---
// These names are also reused below to build the underlying resource IDs,
// assuming the connection name matches the backend resource name (the sample-16 convention).
param cosmosDBConnection      = 'foundrysasiv2sapkcosmosdb'
param azureStorageConnection  = 'foundrysasiv2sapkstorage'
param aiSearchConnection      = 'foundrysasiv2sapksearch'

// --- Capability host name on the new project ---
param projectCapHost = 'caphostproj'

// --- Subscription + RG hosting the underlying Cosmos / Storage / Search resources ---
var depSub = '86eb6d81-d6a8-499f-8fbc-ef7207ccc0c5'
var depRg  = 'rg-foundry-byovnet-demo'

// --- Resource IDs derived from the connection names above ---
param cosmosDBResourceId     = '/subscriptions/${depSub}/resourceGroups/${depRg}/providers/Microsoft.DocumentDB/databaseAccounts/${cosmosDBConnection}'
param azureStorageResourceId = '/subscriptions/${depSub}/resourceGroups/${depRg}/providers/Microsoft.Storage/storageAccounts/${azureStorageConnection}'
param aiSearchResourceId     = '/subscriptions/${depSub}/resourceGroups/${depRg}/providers/Microsoft.Search/searchServices/${aiSearchConnection}'

// Override the auto-generated target connection names if desired:
// param targetCosmosDBConnection      = 'cosmos-projectapimtest'
// param targetAzureStorageConnection  = 'storage-projectapimtest'
// param targetAiSearchConnection      = 'search-projectapimtest'

