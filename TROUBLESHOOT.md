# If any projects still listed, their caphosts must be deleted first
az cognitiveservices account show --name aiservicesgrdc --resource-group rg-foundry-byovnet-pk-v1 --query "properties.allowProjectManagement"

az rest --method GET --url "https://management.azure.com/subscriptions/$(az account show --query id -o tsv)/resourceGroups/rg-foundry-byovnet-pk-v1/providers/Microsoft.CognitiveServices/accounts/aiservicesgrdc/capabilityHosts?api-version=2025-04-01-preview"

az cognitiveservices account show --name foundry-byovnet-eastus2 --resource-group rg-foundry-byovnet-demo --query "name" -o tsv 2>$null

az cognitiveservices account list-deleted --query "[?name=='foundry-byovnet-eastus2'].{name:name, location:location, deletionDate:properties.deletionDate}"

az network vnet subnet show `
  --resource-group rg-foundry-byovnet-demo `
  --vnet-name agent-vnet-test `
  --name agent-subnet `
  --query id -o tsv

# General query to check for subnet serviceassociationlinks
az network vnet subnet show --ids "<agent-subnet-resource-id>" --query "serviceAssociationLinks"

# Query after feeding in agent-subnet-resource-id

az network vnet subnet show --ids "/subscriptions/86eb6d81-d6a8-499f-8fbc-ef7207ccc0c5/resourceGroups/rg-foundry-byovnet-demo/providers/Microsoft.Network/virtualNetworks/agent-vnet-test/subnets/agent-subnet" --query "serviceAssociationLinks"

az rest --method GET --url "https://management.azure.com/subscriptions/86eb6d81-d6a8-499f-8fbc-ef7207ccc0c5/resourceGroups/rg-foundry-byovnet-demo/providers/Microsoft.CognitiveServices/accounts/aiservices-newypea/capabilityHosts?api-version=2025-04-01-preview" --query "value[].{name:name, kind:properties.capabilityHostKind, state:properties.provisioningState}" -o table