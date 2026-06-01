using './main.bicep'

// Values sourced from deployment.json (deployment Microsoft.Template-20260520121411)
param location = 'southindia'
param aiServices = 'aiservices-new'
param modelName = 'gpt-4o'
param modelFormat = 'OpenAI'
param modelVersion = '2024-11-20'
param modelSkuName = 'GlobalStandard'
param modelCapacity = 15
// Pinned to the original deployment so uniqueSuffix resolves to 'grdc' and re-uses existing resources
// param deploymentTimestamp = '20260520064424'
param firstProjectName = 'project'
param projectDescription = 'A project for the AI Foundry account with network secured deployed Agent'
param displayName = 'network secured agent project'

param vnetName = 'agent-vnet-test'
param agentSubnetName = 'agent-subnet-v5'
param peSubnetName = 'pe-subnet'

// Existing resources
param existingVnetResourceId = '/subscriptions/86eb6d81-d6a8-499f-8fbc-ef7207ccc0c5/resourceGroups/rg-foundry-byovnet-demo/providers/Microsoft.Network/virtualNetworks/agent-vnet-test'
param aiSearchResourceId = '/subscriptions/86eb6d81-d6a8-499f-8fbc-ef7207ccc0c5/resourceGroups/rg-foundry-byovnet-demo/providers/Microsoft.Search/searchServices/foundrysasiv2sapksearch'
param azureStorageAccountResourceId = '/subscriptions/86eb6d81-d6a8-499f-8fbc-ef7207ccc0c5/resourceGroups/rg-foundry-byovnet-demo/providers/Microsoft.Storage/storageAccounts/foundrysasiv2sapkstorage'
param azureCosmosDBAccountResourceId = '/subscriptions/86eb6d81-d6a8-499f-8fbc-ef7207ccc0c5/resourceGroups/rg-foundry-byovnet-demo/providers/Microsoft.DocumentDB/databaseAccounts/foundrysasiv2sapkcosmosdb'
param apiManagementResourceId = ''

// Existing private DNS zones (all in rg-foundry-byovnet-demo)
param existingDnsZones = {
  'privatelink.services.ai.azure.com': 'rg-foundry-byovnet-demo'
  'privatelink.openai.azure.com': 'rg-foundry-byovnet-demo'
  'privatelink.cognitiveservices.azure.com': 'rg-foundry-byovnet-demo'
  'privatelink.search.windows.net': 'rg-foundry-byovnet-demo'
  'privatelink.blob.core.windows.net': 'rg-foundry-byovnet-demo'
  'privatelink.documents.azure.com': 'rg-foundry-byovnet-demo'
  'privatelink.azure-api.net': ''
}

param dnsZoneNames = [
  'privatelink.services.ai.azure.com'
  'privatelink.openai.azure.com'
  'privatelink.cognitiveservices.azure.com'
  'privatelink.search.windows.net'
  'privatelink.blob.core.windows.net'
  'privatelink.documents.azure.com'
  'privatelink.azure-api.net'
]

// Network address prefixes (only used when creating a new VNet; ignored since existingVnetResourceId is set)
param vnetAddressPrefix = ''
param agentSubnetPrefix = '192.168.6.0/24'
param peSubnetPrefix = '192.168.1.0/24'

param projectCapHost = 'caphostproj'
