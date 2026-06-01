/*
Private Endpoint and DNS Configuration Module
------------------------------------------
This module configures private network access for Azure services using:

1. Private Endpoints:
   - Creates network interfaces in the specified subnet
   - Establishes private connections to Azure services
   - Enables secure access without public internet exposure

2. Private DNS Zones:
   - Enables custom DNS resolution for private endpoints

3. DNS Zone Links:
   - Links private DNS zones to the VNet
   - Enables name resolution for resources in the VNet
   - Prevents DNS resolution conflicts

Security Benefits:
- Eliminates public internet exposure
- Enables secure access from within VNet
- Prevents data exfiltration through network
*/

// Resource names and identifiers
@description('Name of the AI Foundry account')
param aiAccountName string
@description('Name of the AI Search service')
param aiSearchName string
@description('Name of the storage account')
param storageName string
@description('Name of the Cosmos DB account')
param cosmosDBName string
@description('Name of the API Management service (optional)')
param apiManagementName string = ''
@description('Name of the Vnet')
param vnetName string
@description('Name of the Customer subnet')
param peSubnetName string
@description('Suffix for unique resource names')
param suffix string

@description('Resource Group name for existing Virtual Network (if different from current resource group)')
param vnetResourceGroupName string = resourceGroup().name

@description('Subscription ID for Virtual Network')
param vnetSubscriptionId string = subscription().subscriptionId

@description('Resource Group name for Storage Account')
param storageAccountResourceGroupName string = resourceGroup().name

@description('Subscription ID for Storage account')
param storageAccountSubscriptionId string = subscription().subscriptionId

@description('Subscription ID for AI Search service')
param aiSearchSubscriptionId string = subscription().subscriptionId

@description('Resource Group name for AI Search service')
param aiSearchResourceGroupName string = resourceGroup().name

@description('Subscription ID for Cosmos DB account')
param cosmosDBSubscriptionId string = subscription().subscriptionId

@description('Resource group name for Cosmos DB account')
param cosmosDBResourceGroupName string = resourceGroup().name

@description('Subscription ID for API Management service (optional)')
param apiManagementSubscriptionId string = subscription().subscriptionId

@description('Resource group name for API Management service (optional)')
param apiManagementResourceGroupName string = resourceGroup().name

@description('''Map of DNS zone FQDNs to their location.
Each value is an object { subscriptionId: string, resourceGroupName: string }.
- If resourceGroupName is empty, a new private DNS zone is created in the current resource group and linked to the VNet.
- If resourceGroupName is set, the existing zone is referenced. subscriptionId may be empty to default to the deployment subscription, or set to a different subscription (e.g. a central/hub DNS subscription).''')
param existingDnsZones object = {
  'privatelink.services.ai.azure.com': { subscriptionId: '', resourceGroupName: '' }
  'privatelink.openai.azure.com': { subscriptionId: '', resourceGroupName: '' }
  'privatelink.cognitiveservices.azure.com': { subscriptionId: '', resourceGroupName: '' }
  'privatelink.search.windows.net': { subscriptionId: '', resourceGroupName: '' }
  'privatelink.blob.${environment().suffixes.storage}': { subscriptionId: '', resourceGroupName: '' }
  'privatelink.documents.azure.com': { subscriptionId: '', resourceGroupName: '' }
  'privatelink.azure-api.net': { subscriptionId: '', resourceGroupName: '' }
}

// ---- Resource references ----
resource aiAccount 'Microsoft.CognitiveServices/accounts@2023-05-01' existing = {
  name: aiAccountName
  scope: resourceGroup()
}

resource aiSearch 'Microsoft.Search/searchServices@2023-11-01' existing = {
  name: aiSearchName
  scope: resourceGroup(aiSearchSubscriptionId, aiSearchResourceGroupName)
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageName
  scope: resourceGroup(storageAccountSubscriptionId, storageAccountResourceGroupName)
}

resource cosmosDBAccount 'Microsoft.DocumentDB/databaseAccounts@2024-11-15' existing = {
  name: cosmosDBName
  scope: resourceGroup(cosmosDBSubscriptionId, cosmosDBResourceGroupName)
}

resource apiManagementService 'Microsoft.ApiManagement/service@2023-05-01-preview' existing = if (!empty(apiManagementName)) {
  name: apiManagementName
  scope: resourceGroup(apiManagementSubscriptionId, apiManagementResourceGroupName)
}

// Reference existing network resources
resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: vnetName
  scope: resourceGroup(vnetSubscriptionId, vnetResourceGroupName)
}
resource peSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = {
  parent: vnet
  name: peSubnetName
}

/* -------------------------------------------- AI Foundry Account Private Endpoint -------------------------------------------- */

// Private endpoint for AI Services account
// - Creates network interface in customer hub subnet
// - Establishes private connection to AI Services account
resource aiAccountPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: '${aiAccountName}-private-endpoint'
  location: resourceGroup().location
  properties: {
    subnet: { id: peSubnet.id } // Deploy in customer hub subnet
    privateLinkServiceConnections: [
      {
        name: '${aiAccountName}-private-link-service-connection'
        properties: {
          privateLinkServiceId: aiAccount.id
          groupIds: [ 'account' ] // Target AI Services account
        }
      }
    ]
  }
}

/* -------------------------------------------- AI Search Private Endpoint -------------------------------------------- */

// Private endpoint for AI Search
// - Creates network interface in customer hub subnet
// - Establishes private connection to AI Search service
resource aiSearchPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: '${aiSearchName}-private-endpoint'
  location: resourceGroup().location
  properties: {
    subnet: { id: peSubnet.id } // Deploy in customer hub subnet
    privateLinkServiceConnections: [
      {
        name: '${aiSearchName}-private-link-service-connection'
        properties: {
          privateLinkServiceId: aiSearch.id
          groupIds: [ 'searchService' ] // Target search service
        }
      }
    ]
  }
}

/* -------------------------------------------- Storage Private Endpoint -------------------------------------------- */

// Private endpoint for Storage Account
// - Creates network interface in customer hub subnet
// - Establishes private connection to blob storage
resource storagePrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: '${storageName}-private-endpoint'
  location: resourceGroup().location
  properties: {
    subnet: { id: peSubnet.id } // Deploy in customer hub subnet
    privateLinkServiceConnections: [
      {
        name: '${storageName}-private-link-service-connection'
        properties: {
          privateLinkServiceId: storageAccount.id // Target blob storage
          groupIds: [ 'blob' ]
        }
      }
    ]
  }
}

/*--------------------------------------------- Cosmos DB Private Endpoint -------------------------------------*/

resource cosmosDBPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: '${cosmosDBName}-private-endpoint'
  location: resourceGroup().location
  properties: {
    subnet: { id: peSubnet.id } // Deploy in customer hub subnet
    privateLinkServiceConnections: [
      {
        name: '${cosmosDBName}-private-link-service-connection'
        properties: {
          privateLinkServiceId: cosmosDBAccount.id // Target Cosmos DB account
          groupIds: [ 'Sql' ]
        }
      }
    ]
  }
}

/*--------------------------------------------- API Management Private Endpoint -------------------------------------*/

resource apiManagementPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = if (!empty(apiManagementName)) {
  name: '${apiManagementName}-private-endpoint'
  location: resourceGroup().location
  properties: {
    subnet: { id: peSubnet.id } // Deploy in customer hub subnet
    privateLinkServiceConnections: [
      {
        name: '${apiManagementName}-private-link-service-connection'
        properties: {
          privateLinkServiceId: apiManagementService.id // Target API Management service
          groupIds: [ 'Gateway' ] // Gateway endpoint for API calls
        }
      }
    ]
  }
}

/* -------------------------------------------- Private DNS Zones -------------------------------------------- */

// Format: 1) Private DNS Zone
//         2) Link Private DNS Zone to VNet
//         3) Create DNS Zone Group for Private Endpoint

// Private DNS Zone for AI Services (Account)
// 1) Enables custom DNS resolution for AI Services private endpoint

var aiServicesDnsZoneName = 'privatelink.services.ai.azure.com'
var openAiDnsZoneName = 'privatelink.openai.azure.com'
var cognitiveServicesDnsZoneName = 'privatelink.cognitiveservices.azure.com'
var aiSearchDnsZoneName = 'privatelink.search.windows.net'
var storageDnsZoneName = 'privatelink.blob.${environment().suffixes.storage}'
var cosmosDBDnsZoneName = 'privatelink.documents.azure.com'
var apiManagementDnsZoneName = 'privatelink.azure-api.net'

// ---- DNS Zone Resource Group lookups ----
// Each entry resolves to { subscriptionId, resourceGroupName }.
// Empty resourceGroupName  -> create local zone in this resource group.
// Empty subscriptionId     -> use the deployment subscription.
var aiServicesDnsZoneRG = existingDnsZones[aiServicesDnsZoneName].resourceGroupName
var openAiDnsZoneRG = existingDnsZones[openAiDnsZoneName].resourceGroupName
var cognitiveServicesDnsZoneRG = existingDnsZones[cognitiveServicesDnsZoneName].resourceGroupName
var aiSearchDnsZoneRG = existingDnsZones[aiSearchDnsZoneName].resourceGroupName
var storageDnsZoneRG = existingDnsZones[storageDnsZoneName].resourceGroupName
var cosmosDBDnsZoneRG = existingDnsZones[cosmosDBDnsZoneName].resourceGroupName
var apiManagementDnsZoneRG = existingDnsZones[apiManagementDnsZoneName].resourceGroupName

var aiServicesDnsZoneSub = empty(existingDnsZones[aiServicesDnsZoneName].subscriptionId) ? subscription().subscriptionId : existingDnsZones[aiServicesDnsZoneName].subscriptionId
var openAiDnsZoneSub = empty(existingDnsZones[openAiDnsZoneName].subscriptionId) ? subscription().subscriptionId : existingDnsZones[openAiDnsZoneName].subscriptionId
var cognitiveServicesDnsZoneSub = empty(existingDnsZones[cognitiveServicesDnsZoneName].subscriptionId) ? subscription().subscriptionId : existingDnsZones[cognitiveServicesDnsZoneName].subscriptionId
var aiSearchDnsZoneSub = empty(existingDnsZones[aiSearchDnsZoneName].subscriptionId) ? subscription().subscriptionId : existingDnsZones[aiSearchDnsZoneName].subscriptionId
var storageDnsZoneSub = empty(existingDnsZones[storageDnsZoneName].subscriptionId) ? subscription().subscriptionId : existingDnsZones[storageDnsZoneName].subscriptionId
var cosmosDBDnsZoneSub = empty(existingDnsZones[cosmosDBDnsZoneName].subscriptionId) ? subscription().subscriptionId : existingDnsZones[cosmosDBDnsZoneName].subscriptionId
var apiManagementDnsZoneSub = empty(existingDnsZones[apiManagementDnsZoneName].subscriptionId) ? subscription().subscriptionId : existingDnsZones[apiManagementDnsZoneName].subscriptionId

// ---- DNS Zone Resources and References ----
resource aiServicesPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = if (empty(aiServicesDnsZoneRG)) {
  name: aiServicesDnsZoneName
  location: 'global'
}

// Reference existing private DNS zone if provided
resource existingAiServicesPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' existing = if (!empty(aiServicesDnsZoneRG)) {
  name: aiServicesDnsZoneName
  scope: resourceGroup(aiServicesDnsZoneSub, aiServicesDnsZoneRG)
}
//creating condition if user pass existing dns zones or not
var aiServicesDnsZoneId = empty(aiServicesDnsZoneRG) ? aiServicesPrivateDnsZone.id : existingAiServicesPrivateDnsZone.id

resource openAiPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = if (empty(openAiDnsZoneRG)) {
  name: openAiDnsZoneName
  location: 'global'
}

// Reference existing private DNS zone if provided
resource existingOpenAiPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' existing = if (!empty(openAiDnsZoneRG)) {
  name: openAiDnsZoneName
  scope: resourceGroup(openAiDnsZoneSub, openAiDnsZoneRG)
}
//creating condition if user pass existing dns zones or not
var openAiDnsZoneId = empty(openAiDnsZoneRG) ? openAiPrivateDnsZone.id : existingOpenAiPrivateDnsZone.id

resource cognitiveServicesPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = if (empty(cognitiveServicesDnsZoneRG)) {
  name: cognitiveServicesDnsZoneName
  location: 'global'
}

// Reference existing private DNS zone if provided
resource existingCognitiveServicesPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' existing = if (!empty(cognitiveServicesDnsZoneRG)) {
  name: cognitiveServicesDnsZoneName
  scope: resourceGroup(cognitiveServicesDnsZoneSub, cognitiveServicesDnsZoneRG)
}
//creating condition if user pass existing dns zones or not
var cognitiveServicesDnsZoneId = empty(cognitiveServicesDnsZoneRG) ? cognitiveServicesPrivateDnsZone.id : existingCognitiveServicesPrivateDnsZone.id

resource aiSearchPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = if (empty(aiSearchDnsZoneRG)) {
  name: aiSearchDnsZoneName
  location: 'global'
}

// Reference existing private DNS zone if provided
resource existingAiSearchPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' existing = if (!empty(aiSearchDnsZoneRG)) {
  name: aiSearchDnsZoneName
  scope: resourceGroup(aiSearchDnsZoneSub, aiSearchDnsZoneRG)
}
//creating condition if user pass existing dns zones or not
var aiSearchDnsZoneId = empty(aiSearchDnsZoneRG) ? aiSearchPrivateDnsZone.id : existingAiSearchPrivateDnsZone.id

resource storagePrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = if (empty(storageDnsZoneRG)) {
  name: storageDnsZoneName
  location: 'global'
}

// Reference existing private DNS zone if provided
resource existingStoragePrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' existing = if (!empty(storageDnsZoneRG)) {
  name: storageDnsZoneName
  scope: resourceGroup(storageDnsZoneSub, storageDnsZoneRG)
}
//creating condition if user pass existing dns zones or not
var storageDnsZoneId = empty(storageDnsZoneRG) ? storagePrivateDnsZone.id : existingStoragePrivateDnsZone.id

resource cosmosDBPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = if (empty(cosmosDBDnsZoneRG)) {
  name: cosmosDBDnsZoneName
  location: 'global'
}

// Reference existing private DNS zone if provided
resource existingCosmosDBPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' existing = if (!empty(cosmosDBDnsZoneRG)) {
  name: cosmosDBDnsZoneName
  scope: resourceGroup(cosmosDBDnsZoneSub, cosmosDBDnsZoneRG)
}
//creating condition if user pass existing dns zones or not
var cosmosDBDnsZoneId = empty(cosmosDBDnsZoneRG) ? cosmosDBPrivateDnsZone.id : existingCosmosDBPrivateDnsZone.id

resource apiManagementPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = if (empty(apiManagementDnsZoneRG) && !empty(apiManagementName)) {
  name: apiManagementDnsZoneName
  location: 'global'
}

// Reference existing private DNS zone if provided
resource existingApiManagementPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' existing = if (!empty(apiManagementDnsZoneRG) && !empty(apiManagementName)) {
  name: apiManagementDnsZoneName
  scope: resourceGroup(apiManagementDnsZoneSub, apiManagementDnsZoneRG)
}
//creating condition if user pass existing dns zones or not
var apiManagementDnsZoneId = !empty(apiManagementName) ? (empty(apiManagementDnsZoneRG) ? apiManagementPrivateDnsZone.id : existingApiManagementPrivateDnsZone.id) : ''

// ---- DNS VNet Links ----
resource aiServicesLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = if (empty(aiServicesDnsZoneRG)) {
  parent: aiServicesPrivateDnsZone
  location: 'global'
  name: 'aiServices-${suffix}-link'
  properties: {
    virtualNetwork: { id: vnet.id }
    registrationEnabled: false
  }
}
resource openAiLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = if (empty(openAiDnsZoneRG)) {
  parent: openAiPrivateDnsZone
  location: 'global'
  name: 'aiServicesOpenAI-${suffix}-link'
  properties: {
    virtualNetwork: { id: vnet.id }
    registrationEnabled: false
  }
}
resource cognitiveServicesLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = if (empty(cognitiveServicesDnsZoneRG)) {
  parent: cognitiveServicesPrivateDnsZone
  location: 'global'
  name: 'aiServicesCognitiveServices-${suffix}-link'
  properties: {
    virtualNetwork: { id: vnet.id }
    registrationEnabled: false
  }
}
resource aiSearchLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = if (empty(aiSearchDnsZoneRG)) {
  parent: aiSearchPrivateDnsZone
  location: 'global'
  name: 'aiSearch-${suffix}-link'
  properties: {
    virtualNetwork: { id: vnet.id }
    registrationEnabled: false
  }
}
resource storageLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = if (empty(storageDnsZoneRG)) {
  parent: storagePrivateDnsZone
  location: 'global'
  name: 'storage-${suffix}-link'
  properties: {
    virtualNetwork: { id: vnet.id }
    registrationEnabled: false
  }
}
resource cosmosDBLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = if (empty(cosmosDBDnsZoneRG)) {
  parent: cosmosDBPrivateDnsZone
  location: 'global'
  name: 'cosmosDB-${suffix}-link'
  properties: {
    virtualNetwork: { id: vnet.id }
    registrationEnabled: false
  }
}
resource apiManagementLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = if (empty(apiManagementDnsZoneRG) && !empty(apiManagementName)) {
  parent: apiManagementPrivateDnsZone
  location: 'global'
  name: 'apiManagement-${suffix}-link'
  properties: {
    virtualNetwork: { id: vnet.id }
    registrationEnabled: false
  }
}

// ---- DNS Zone Groups ----
resource aiServicesDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: aiAccountPrivateEndpoint
  name: '${aiAccountName}-dns-group'
  properties: {
    privateDnsZoneConfigs: [
      { name: '${aiAccountName}-dns-aiserv-config', properties: { privateDnsZoneId: aiServicesDnsZoneId } }
      { name: '${aiAccountName}-dns-openai-config', properties: { privateDnsZoneId: openAiDnsZoneId } }
      { name: '${aiAccountName}-dns-cogserv-config', properties: { privateDnsZoneId: cognitiveServicesDnsZoneId } }
    ]
  }
  dependsOn: [
    empty(aiServicesDnsZoneRG) ? aiServicesLink : null
    empty(openAiDnsZoneRG) ? openAiLink : null
    empty(cognitiveServicesDnsZoneRG) ? cognitiveServicesLink : null
  ]
}
resource aiSearchDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: aiSearchPrivateEndpoint
  name: '${aiSearchName}-dns-group'
  properties: {
    privateDnsZoneConfigs: [
      { name: '${aiSearchName}-dns-config', properties: { privateDnsZoneId: aiSearchDnsZoneId } }
    ]
  }
  dependsOn: [
    empty(aiSearchDnsZoneRG) ? aiSearchLink : null
  ]
}
resource storageDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: storagePrivateEndpoint
  name: '${storageName}-dns-group'
  properties: {
    privateDnsZoneConfigs: [
      { name: '${storageName}-dns-config', properties: { privateDnsZoneId: storageDnsZoneId } }
    ]
  }
  dependsOn: [
    empty(storageDnsZoneRG) ? storageLink : null
  ]
}
resource cosmosDBDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: cosmosDBPrivateEndpoint
  name: '${cosmosDBName}-dns-group'
  properties: {
    privateDnsZoneConfigs: [
      { name: '${cosmosDBName}-dns-config', properties: { privateDnsZoneId: cosmosDBDnsZoneId } }
    ]
  }
  dependsOn: [
    empty(cosmosDBDnsZoneRG) ? cosmosDBLink : null
  ]
}
resource apiManagementDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = if (!empty(apiManagementName)) {
  parent: apiManagementPrivateEndpoint
  name: '${apiManagementName}-dns-group'
  properties: {
    privateDnsZoneConfigs: [
      { name: '${apiManagementName}-dns-config', properties: { privateDnsZoneId: apiManagementDnsZoneId } }
    ]
  }
  dependsOn: [
    apiManagementLink
  ]
}
