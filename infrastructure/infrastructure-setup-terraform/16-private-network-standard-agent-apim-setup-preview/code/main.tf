########## Create private network infrastructure with Standard Agent and API Management
##########

## NOTE: This is a complex advanced scenario combining private networking,
## standard agent setup (BYOS), and Azure API Management integration

## Get subscription data
data "azurerm_client_config" "current" {}

## Create a random string for unique naming
resource "random_string" "unique" {
  length      = 4
  min_numeric = 4
  numeric     = true
  special     = false
  lower       = true
  upper       = false
}

locals {
  account_name = lower("${var.ai_services_name_prefix}${random_string.unique.result}")

  # ---- APIM mode ----
  apim_create = var.apim_mode == "create-internal"
  apim_byo    = var.apim_mode == "byo-standardv2"

  # ---- BYO shared resources ----
  # true = create here, false = reference existing via var.existing_<x>_id
  rg_create      = var.existing_resource_group_name == ""
  vnet_create    = var.existing_vnet_id == ""
  storage_create = var.existing_storage_account_id == ""
  search_create  = var.existing_ai_search_id == ""
  cosmos_create  = var.existing_cosmos_db_account_id == ""

  current_subscription_id = data.azurerm_client_config.current.subscription_id

  # Resource group. For existing RG we construct the ARM ID assuming same-sub (Bicep parity).
  rg_name = local.rg_create ? azurerm_resource_group.rg[0].name : var.existing_resource_group_name
  rg_id   = local.rg_create ? azurerm_resource_group.rg[0].id : "/subscriptions/${local.current_subscription_id}/resourceGroups/${var.existing_resource_group_name}"

  # VNet + subnets. For existing VNet we parse name/rg from the ARM ID and construct subnet IDs by
  # appending /subnets/<name> — no data source / provider alias required (cross-sub supported).
  vnet_id_parts   = local.vnet_create ? [] : split("/", var.existing_vnet_id)
  vnet_id         = local.vnet_create ? azurerm_virtual_network.vnet[0].id : var.existing_vnet_id
  vnet_name       = local.vnet_create ? azurerm_virtual_network.vnet[0].name : local.vnet_id_parts[8]
  pe_subnet_id    = local.vnet_create ? azurerm_subnet.subnet_pe[0].id : "${var.existing_vnet_id}/subnets/${var.existing_pe_subnet_name}"
  agent_subnet_id = local.vnet_create ? azurerm_subnet.subnet_agent[0].id : "${var.existing_vnet_id}/subnets/${var.existing_agent_subnet_name}"
  apim_subnet_id  = local.apim_create ? (local.vnet_create ? azurerm_subnet.subnet_apim[0].id : "${var.existing_vnet_id}/subnets/${var.existing_apim_subnet_name}") : ""

  # Storage. ARM ID shape: /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Storage/storageAccounts/{name}
  # split("/", id) => indexes 2=sub, 4=rg, 8=name. Blob endpoint constructed for commercial cloud.
  storage_id_parts      = local.storage_create ? [] : split("/", var.existing_storage_account_id)
  storage_id            = local.storage_create ? azurerm_storage_account.storage[0].id : var.existing_storage_account_id
  storage_name          = local.storage_create ? azurerm_storage_account.storage[0].name : local.storage_id_parts[8]
  storage_blob_endpoint = local.storage_create ? azurerm_storage_account.storage[0].primary_blob_endpoint : "https://${local.storage_id_parts[8]}.blob.core.windows.net/"

  # AI Search
  search_id_parts = local.search_create ? [] : split("/", var.existing_ai_search_id)
  search_id       = local.search_create ? azurerm_search_service.search[0].id : var.existing_ai_search_id
  search_name     = local.search_create ? azurerm_search_service.search[0].name : local.search_id_parts[8]

  # Cosmos DB. resource_group_name and account_name are needed for azurerm_cosmosdb_sql_role_assignment.
  cosmos_id_parts = local.cosmos_create ? [] : split("/", var.existing_cosmos_db_account_id)
  cosmos_id       = local.cosmos_create ? azurerm_cosmosdb_account.cosmos[0].id : var.existing_cosmos_db_account_id
  cosmos_name     = local.cosmos_create ? azurerm_cosmosdb_account.cosmos[0].name : local.cosmos_id_parts[8]
  cosmos_rg       = local.cosmos_create ? local.rg_name : local.cosmos_id_parts[4]
  cosmos_endpoint = local.cosmos_create ? azurerm_cosmosdb_account.cosmos[0].endpoint : "https://${local.cosmos_name}.documents.azure.com:443/"

  # ---- Cross-subscription / central DNS resolution ----
  # For each private DNS zone, decide whether to CREATE it locally or REFERENCE an existing one
  # (optionally in a different subscription, e.g. central hub DNS). Empty resource_group_name = create.

  # AI Foundry account PE needs all 3 Cognitive Services privatelink zones registered
  # (services.ai, openai, cognitiveservices) — matches Bicep behavior.
  dns_zone_names = {
    ai_services = "privatelink.services.ai.azure.com"
    openai      = "privatelink.openai.azure.com"
    ai_foundry  = "privatelink.cognitiveservices.azure.com"
    storage     = "privatelink.blob.core.windows.net"
    search      = "privatelink.search.windows.net"
    cosmos      = "privatelink.documents.azure.com"
    apim        = "privatelink.azure-api.net"
  }

  dns_zone_config = {
    for key, zone_name in local.dns_zone_names :
    key => lookup(var.existing_dns_zones, zone_name, { subscription_id = "", resource_group_name = "" })
  }

  dns_zone_is_existing = {
    for key, cfg in local.dns_zone_config :
    key => cfg.resource_group_name != ""
  }

  # Resolved zone IDs (used in each PE's private_dns_zone_group). For existing zones we construct
  # the ARM ID directly — no data source / provider alias needed, matching how Bicep `existing`
  # references work for ID composition.
  dns_zone_ids = {
    ai_services = local.dns_zone_is_existing.ai_services ? "/subscriptions/${coalesce(local.dns_zone_config.ai_services.subscription_id, local.current_subscription_id)}/resourceGroups/${local.dns_zone_config.ai_services.resource_group_name}/providers/Microsoft.Network/privateDnsZones/${local.dns_zone_names.ai_services}" : azurerm_private_dns_zone.ai_services[0].id
    openai      = local.dns_zone_is_existing.openai ? "/subscriptions/${coalesce(local.dns_zone_config.openai.subscription_id, local.current_subscription_id)}/resourceGroups/${local.dns_zone_config.openai.resource_group_name}/providers/Microsoft.Network/privateDnsZones/${local.dns_zone_names.openai}" : azurerm_private_dns_zone.openai[0].id
    ai_foundry  = local.dns_zone_is_existing.ai_foundry ? "/subscriptions/${coalesce(local.dns_zone_config.ai_foundry.subscription_id, local.current_subscription_id)}/resourceGroups/${local.dns_zone_config.ai_foundry.resource_group_name}/providers/Microsoft.Network/privateDnsZones/${local.dns_zone_names.ai_foundry}" : azurerm_private_dns_zone.ai_foundry[0].id
    storage     = local.dns_zone_is_existing.storage ? "/subscriptions/${coalesce(local.dns_zone_config.storage.subscription_id, local.current_subscription_id)}/resourceGroups/${local.dns_zone_config.storage.resource_group_name}/providers/Microsoft.Network/privateDnsZones/${local.dns_zone_names.storage}" : azurerm_private_dns_zone.storage[0].id
    search      = local.dns_zone_is_existing.search ? "/subscriptions/${coalesce(local.dns_zone_config.search.subscription_id, local.current_subscription_id)}/resourceGroups/${local.dns_zone_config.search.resource_group_name}/providers/Microsoft.Network/privateDnsZones/${local.dns_zone_names.search}" : azurerm_private_dns_zone.search[0].id
    cosmos      = local.dns_zone_is_existing.cosmos ? "/subscriptions/${coalesce(local.dns_zone_config.cosmos.subscription_id, local.current_subscription_id)}/resourceGroups/${local.dns_zone_config.cosmos.resource_group_name}/providers/Microsoft.Network/privateDnsZones/${local.dns_zone_names.cosmos}" : azurerm_private_dns_zone.cosmos[0].id
    apim        = local.dns_zone_is_existing.apim ? "/subscriptions/${coalesce(local.dns_zone_config.apim.subscription_id, local.current_subscription_id)}/resourceGroups/${local.dns_zone_config.apim.resource_group_name}/providers/Microsoft.Network/privateDnsZones/${local.dns_zone_names.apim}" : azurerm_private_dns_zone.apim[0].id
  }
}

## Create a resource group (only when existing_resource_group_name is empty).
resource "azurerm_resource_group" "rg" {
  count    = local.rg_create ? 1 : 0
  name     = "rg-aifoundry${random_string.unique.result}"
  location = var.location
}

## Create Virtual Network (only when existing_vnet_id is empty).
resource "azurerm_virtual_network" "vnet" {
  count               = local.vnet_create ? 1 : 0
  name                = "vnet-aifoundry${random_string.unique.result}"
  address_space       = var.vnet_address_space
  location            = var.location
  resource_group_name = local.rg_name
}

## Create Subnet for private endpoints (only when creating the VNet here).
resource "azurerm_subnet" "subnet_pe" {
  count                = local.vnet_create ? 1 : 0
  name                 = "subnet-private-endpoints"
  resource_group_name  = local.rg_name
  virtual_network_name = local.vnet_name
  address_prefixes     = [var.subnet_private_endpoints_prefix]
}

## Create Subnet for the Foundry agent runtime (only when creating the VNet here).
## Delegated to Microsoft.App/environments — required for networkInjections (scenario=agent).
resource "azurerm_subnet" "subnet_agent" {
  count                = local.vnet_create ? 1 : 0
  name                 = "subnet-agent"
  resource_group_name  = local.rg_name
  virtual_network_name = local.vnet_name
  address_prefixes     = [cidrsubnet(var.vnet_address_space[0], 8, 0)]

  delegation {
    name = "Microsoft.App/environments"
    service_delegation {
      name = "Microsoft.App/environments"
    }
  }
}

## BYO VNet: patch the existing agent subnet to add the Microsoft.App/environments delegation
## (Bicep parity). PATCH is used so other subnet properties are preserved. The subnet must be
## empty of incompatible resources (e.g. private endpoint NICs) for delegation to succeed.
resource "azapi_update_resource" "agent_subnet_delegation" {
  count       = local.vnet_create ? 0 : 1
  type        = "Microsoft.Network/virtualNetworks/subnets@2024-05-01"
  resource_id = local.agent_subnet_id

  body = {
    properties = {
      delegations = [
        {
          name = "Microsoft.App/environments"
          properties = {
            serviceName = "Microsoft.App/environments"
          }
        }
      ]
    }
  }

  depends_on = [
    azurerm_private_endpoint.storage,
    azurerm_private_endpoint.search,
    azurerm_private_endpoint.cosmos,
    azurerm_private_endpoint.apim_byo,
  ]
}

## Create Subnet for API Management (only when creating an Internal-VNet APIM here AND creating the VNet here).
resource "azurerm_subnet" "subnet_apim" {
  count                = local.apim_create && local.vnet_create ? 1 : 0
  name                 = "subnet-apim"
  resource_group_name  = local.rg_name
  virtual_network_name = local.vnet_name
  address_prefixes     = [var.subnet_apim_prefix]
}

## NSG required for APIM internal VNet deployment
resource "azurerm_network_security_group" "apim" {
  count               = local.apim_create ? 1 : 0
  name                = "nsg-apim-${random_string.unique.result}"
  location            = var.location
  resource_group_name = local.rg_name

  ## Inbound rules
  security_rule {
    name                       = "AllowAPIMManagement"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3443"
    source_address_prefix      = "ApiManagement"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "AllowAzureLoadBalancer"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "6390"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "AllowHTTPSInbound"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  ## Outbound rules required for APIM dependencies
  security_rule {
    name                       = "AllowStorageOutbound"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "Storage"
  }

  security_rule {
    name                       = "AllowSQLOutbound"
    priority                   = 110
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "1433"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "Sql"
  }

  security_rule {
    name                       = "AllowKeyVaultOutbound"
    priority                   = 120
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "AzureKeyVault"
  }

  security_rule {
    name                       = "AllowMonitorOutbound"
    priority                   = 130
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["443", "1886"]
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "AzureMonitor"
  }

  security_rule {
    name                       = "AllowEntraIDOutbound"
    priority                   = 140
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "AzureActiveDirectory"
  }
}

resource "azurerm_subnet_network_security_group_association" "apim" {
  count                     = local.apim_create && local.vnet_create ? 1 : 0
  subnet_id                 = azurerm_subnet.subnet_apim[0].id
  network_security_group_id = azurerm_network_security_group.apim[0].id
}

## Create Private DNS Zones
## Each zone is created locally only when var.existing_dns_zones for that zone has an empty
## resource_group_name. Otherwise the existing zone is referenced via its constructed ARM ID
## (see locals.dns_zone_ids), supporting central / cross-subscription DNS.
resource "azurerm_private_dns_zone" "ai_services" {
  count               = local.dns_zone_is_existing.ai_services ? 0 : 1
  name                = local.dns_zone_names.ai_services
  resource_group_name = local.rg_name
}

resource "azurerm_private_dns_zone" "openai" {
  count               = local.dns_zone_is_existing.openai ? 0 : 1
  name                = local.dns_zone_names.openai
  resource_group_name = local.rg_name
}

resource "azurerm_private_dns_zone" "ai_foundry" {
  count               = local.dns_zone_is_existing.ai_foundry ? 0 : 1
  name                = local.dns_zone_names.ai_foundry
  resource_group_name = local.rg_name
}

resource "azurerm_private_dns_zone" "storage" {
  count               = local.dns_zone_is_existing.storage ? 0 : 1
  name                = local.dns_zone_names.storage
  resource_group_name = local.rg_name
}

resource "azurerm_private_dns_zone" "search" {
  count               = local.dns_zone_is_existing.search ? 0 : 1
  name                = local.dns_zone_names.search
  resource_group_name = local.rg_name
}

resource "azurerm_private_dns_zone" "cosmos" {
  count               = local.dns_zone_is_existing.cosmos ? 0 : 1
  name                = local.dns_zone_names.cosmos
  resource_group_name = local.rg_name
}

## APIM zone. APIM is deployed in Internal VNet mode (not StandardV2 + PE), so there is no APIM
## private endpoint and no private_dns_zone_group to attach. The zone + VNet link still let the
## VNet resolve the APIM gateway hostname — but the user must manually create an A record
## (e.g. `apim-xxxx` -> APIM private IP). For central-DNS scenarios the hub team owns both.
resource "azurerm_private_dns_zone" "apim" {
  count               = local.dns_zone_is_existing.apim ? 0 : 1
  name                = local.dns_zone_names.apim
  resource_group_name = local.rg_name
}

## Link DNS zones to VNet (only for locally-created zones; for existing/central zones the hub team
## owns the VNet link).
resource "azurerm_private_dns_zone_virtual_network_link" "ai_services" {
  count                 = local.dns_zone_is_existing.ai_services ? 0 : 1
  name                  = "vnet-link-ai-services"
  resource_group_name   = local.rg_name
  private_dns_zone_name = azurerm_private_dns_zone.ai_services[0].name
  virtual_network_id    = local.vnet_id
}

resource "azurerm_private_dns_zone_virtual_network_link" "openai" {
  count                 = local.dns_zone_is_existing.openai ? 0 : 1
  name                  = "vnet-link-openai"
  resource_group_name   = local.rg_name
  private_dns_zone_name = azurerm_private_dns_zone.openai[0].name
  virtual_network_id    = local.vnet_id
}

resource "azurerm_private_dns_zone_virtual_network_link" "ai_foundry" {
  count                 = local.dns_zone_is_existing.ai_foundry ? 0 : 1
  name                  = "vnet-link-ai-foundry"
  resource_group_name   = local.rg_name
  private_dns_zone_name = azurerm_private_dns_zone.ai_foundry[0].name
  virtual_network_id    = local.vnet_id
}

resource "azurerm_private_dns_zone_virtual_network_link" "storage" {
  count                 = local.dns_zone_is_existing.storage ? 0 : 1
  name                  = "vnet-link-storage"
  resource_group_name   = local.rg_name
  private_dns_zone_name = azurerm_private_dns_zone.storage[0].name
  virtual_network_id    = local.vnet_id
}

resource "azurerm_private_dns_zone_virtual_network_link" "search" {
  count                 = local.dns_zone_is_existing.search ? 0 : 1
  name                  = "vnet-link-search"
  resource_group_name   = local.rg_name
  private_dns_zone_name = azurerm_private_dns_zone.search[0].name
  virtual_network_id    = local.vnet_id
}

resource "azurerm_private_dns_zone_virtual_network_link" "cosmos" {
  count                 = local.dns_zone_is_existing.cosmos ? 0 : 1
  name                  = "vnet-link-cosmos"
  resource_group_name   = local.rg_name
  private_dns_zone_name = azurerm_private_dns_zone.cosmos[0].name
  virtual_network_id    = local.vnet_id
}

resource "azurerm_private_dns_zone_virtual_network_link" "apim" {
  count                 = local.dns_zone_is_existing.apim ? 0 : 1
  name                  = "vnet-link-apim"
  resource_group_name   = local.rg_name
  private_dns_zone_name = azurerm_private_dns_zone.apim[0].name
  virtual_network_id    = local.vnet_id
}

## Create Storage Account with private endpoint (skip create if existing_storage_account_id is set).
resource "azurerm_storage_account" "storage" {
  count                    = local.storage_create ? 1 : 0
  name                     = "aifoundry${random_string.unique.result}stor"
  resource_group_name      = local.rg_name
  location                 = var.location
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "ZRS"

  shared_access_key_enabled       = false
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  public_network_access_enabled   = false

  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }
}

resource "azurerm_private_endpoint" "storage" {
  name                = "pe-storage-${random_string.unique.result}"
  location            = var.location
  resource_group_name = local.rg_name
  subnet_id           = local.pe_subnet_id

  private_service_connection {
    name                           = "psc-storage"
    private_connection_resource_id = local.storage_id
    is_manual_connection           = false
    subresource_names              = ["blob"]
  }

  private_dns_zone_group {
    name                 = "storage-dns-zone-group"
    private_dns_zone_ids = [local.dns_zone_ids.storage]
  }
}

## Create AI Search with private endpoint (skip create if existing_ai_search_id is set).
resource "azurerm_search_service" "search" {
  count               = local.search_create ? 1 : 0
  name                = replace("aifoundry-${random_string.unique.result}-search", "_", "-")
  resource_group_name = local.rg_name
  location            = var.location
  sku                 = "standard"

  local_authentication_enabled  = true
  authentication_failure_mode   = "http401WithBearerChallenge"
  public_network_access_enabled = false
}

resource "azurerm_private_endpoint" "search" {
  name                = "pe-search-${random_string.unique.result}"
  location            = var.location
  resource_group_name = local.rg_name
  subnet_id           = local.pe_subnet_id

  private_service_connection {
    name                           = "psc-search"
    private_connection_resource_id = local.search_id
    is_manual_connection           = false
    subresource_names              = ["searchService"]
  }

  private_dns_zone_group {
    name                 = "search-dns-zone-group"
    private_dns_zone_ids = [local.dns_zone_ids.search]
  }
}

## Create Cosmos DB with private endpoint (skip create if existing_cosmos_db_account_id is set).
resource "azurerm_cosmosdb_account" "cosmos" {
  count                             = local.cosmos_create ? 1 : 0
  name                              = "aifoundry${random_string.unique.result}cosmos"
  location                          = var.location
  resource_group_name               = local.rg_name
  offer_type                        = "Standard"
  kind                              = "GlobalDocumentDB"
  public_network_access_enabled     = false
  is_virtual_network_filter_enabled = true

  consistency_policy {
    consistency_level = "Session"
  }

  geo_location {
    location          = var.location
    failover_priority = 0
  }
}

resource "azurerm_private_endpoint" "cosmos" {
  name                = "pe-cosmos-${random_string.unique.result}"
  location            = var.location
  resource_group_name = local.rg_name
  subnet_id           = local.pe_subnet_id

  private_service_connection {
    name                           = "psc-cosmos"
    private_connection_resource_id = local.cosmos_id
    is_manual_connection           = false
    subresource_names              = ["Sql"]
  }

  private_dns_zone_group {
    name                 = "cosmos-dns-zone-group"
    private_dns_zone_ids = [local.dns_zone_ids.cosmos]
  }
}

## Create AI Foundry account with private endpoint
resource "azapi_resource" "ai_foundry" {
  type      = "Microsoft.CognitiveServices/accounts@2025-04-01-preview"
  name      = local.account_name
  location  = var.location
  parent_id = local.rg_id

  identity {
    type = "SystemAssigned"
  }

  body = {
    kind = "AIServices"
    sku = {
      name = "S0"
    }
    properties = {
      allowProjectManagement = true
      customSubDomainName    = local.account_name
      publicNetworkAccess    = "Disabled"
      disableLocalAuth       = true
      networkAcls = {
        defaultAction       = "Deny"
        virtualNetworkRules = []
        ipRules             = []
      }
      networkInjections = [
        {
          scenario                   = "agent"
          subnetArmId                = local.agent_subnet_id
          useMicrosoftManagedNetwork = false
        }
      ]
    }
  }

  depends_on = [azapi_update_resource.agent_subnet_delegation]
}

resource "azurerm_private_endpoint" "ai_foundry" {
  name                = "pe-ai-foundry-${random_string.unique.result}"
  location            = var.location
  resource_group_name = local.rg_name
  subnet_id           = local.pe_subnet_id

  private_service_connection {
    name                           = "psc-ai-foundry"
    private_connection_resource_id = azapi_resource.ai_foundry.id
    is_manual_connection           = false
    subresource_names              = ["account"]
  }

  private_dns_zone_group {
    name = "ai-foundry-dns-zone-group"
    private_dns_zone_ids = [
      local.dns_zone_ids.ai_services,
      local.dns_zone_ids.openai,
      local.dns_zone_ids.ai_foundry,
    ]
  }
}

## Create API Management with VNet integration (create-internal mode only).
resource "azurerm_api_management" "apim" {
  count               = local.apim_create ? 1 : 0
  name                = "apim-${random_string.unique.result}"
  location            = var.location
  resource_group_name = local.rg_name
  publisher_name      = var.apim_publisher_name
  publisher_email     = var.apim_publisher_email
  sku_name            = "${var.apim_sku}_1"

  virtual_network_type = "Internal"

  virtual_network_configuration {
    subnet_id = local.apim_subnet_id
  }

  depends_on = [azurerm_subnet_network_security_group_association.apim]
}

## BYO StandardV2 APIM: create a Gateway private endpoint for the existing APIM and register it
## in privatelink.azure-api.net. The PE resource ID may live in a different subscription;
## auto-approval requires the deploying identity to have permission to create PE connections on
## the APIM (e.g. Network Contributor / approve role) or that the APIM is configured for
## auto-approval.
resource "azurerm_private_endpoint" "apim_byo" {
  count               = local.apim_byo ? 1 : 0
  name                = "pe-apim-${random_string.unique.result}"
  location            = var.location
  resource_group_name = local.rg_name
  subnet_id           = local.pe_subnet_id

  private_service_connection {
    name                           = "psc-apim"
    private_connection_resource_id = var.existing_apim_id
    is_manual_connection           = false
    subresource_names              = ["Gateway"]
  }

  private_dns_zone_group {
    name                 = "apim-dns-zone-group"
    private_dns_zone_ids = [local.dns_zone_ids.apim]
  }

  lifecycle {
    precondition {
      condition     = !local.apim_byo || (length(var.existing_apim_id) > 0 && length(var.existing_apim_gateway_url) > 0)
      error_message = "apim_mode = byo-standardv2 requires both existing_apim_id and existing_apim_gateway_url to be set."
    }
  }
}

## ---- Pre-project: private endpoints only ----
## The Foundry account needs its private endpoint live before we add the project (so the project's
## management traffic resolves over the spoke VNet). RBAC is granted to the PROJECT identity, so
## it must wait until after the project exists; see the role assignments below ai_project.
resource "time_sleep" "wait_for_resources" {
  depends_on = [
    azurerm_private_endpoint.ai_foundry,
    azurerm_private_endpoint.storage,
    azurerm_private_endpoint.search,
    azurerm_private_endpoint.cosmos,
    azurerm_api_management.apim,
    azurerm_private_endpoint.apim_byo,
  ]
  create_duration = "120s"
}

## Create AI Foundry project
resource "azapi_resource" "ai_project" {
  type      = "Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview"
  name      = var.project_name
  location  = var.location
  parent_id = azapi_resource.ai_foundry.id

  identity {
    type = "SystemAssigned"
  }

  body = {
    properties = {}
  }

  # internalId is the raw 32-char workspace id used by post-caphost role-assignment conditions.
  response_export_values = ["properties.internalId"]

  depends_on = [time_sleep.wait_for_resources]
}

# Format internalId (32 hex chars) into a standard 8-4-4-4-12 GUID string for use in the storage
# blob role assignment condition and the post-caphost cosmos role assignment.
locals {
  project_internal_id = azapi_resource.ai_project.output.properties.internalId
  project_workspace_id_guid = format(
    "%s-%s-%s-%s-%s",
    substr(local.project_internal_id, 0, 8),
    substr(local.project_internal_id, 8, 4),
    substr(local.project_internal_id, 12, 4),
    substr(local.project_internal_id, 16, 4),
    substr(local.project_internal_id, 20, 12),
  )
}

## ---- Pre-caphost RBAC granted to the PROJECT managed identity ----
## The capability host create runs as the project MSI and writes to the BYO storage / search /
## cosmos resources during activation. Without these roles the caphost PUT fails with:
##   "A Storage Container blob for Agents is Forbidden due to missing appropriate RBAC ..."
## Mirrors the Bicep modules azure-storage-account-role-assignment.bicep,
## ai-search-role-assignments.bicep, cosmosdb-account-role-assignment.bicep.

resource "azurerm_role_assignment" "project_storage_blob_data_contributor" {
  scope                = local.storage_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azapi_resource.ai_project.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "project_search_index_data_contributor" {
  scope                = local.search_id
  role_definition_name = "Search Index Data Contributor"
  principal_id         = azapi_resource.ai_project.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "project_search_service_contributor" {
  scope                = local.search_id
  role_definition_name = "Search Service Contributor"
  principal_id         = azapi_resource.ai_project.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

# Cosmos DB Operator is the CONTROL-plane (ARM RBAC) role the caphost needs to create databases
# / containers under the account during activation. The data-plane Built-in Data Contributor on
# the `enterprise_memory` database is granted post-caphost further below.
resource "azurerm_role_assignment" "project_cosmos_db_operator" {
  scope                = local.cosmos_id
  role_definition_name = "Cosmos DB Operator"
  principal_id         = azapi_resource.ai_project.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

## Wait for project-MSI RBAC to propagate before caphost create. 120s is the same buffer the
## Bicep template implicitly relies on via deployment ordering; Azure ARM RBAC is eventually
## consistent and the caphost PUT runs as the project identity, so we need this delay.
resource "time_sleep" "wait_for_project_rbac" {
  depends_on = [
    azurerm_role_assignment.project_storage_blob_data_contributor,
    azurerm_role_assignment.project_search_index_data_contributor,
    azurerm_role_assignment.project_search_service_contributor,
    azurerm_role_assignment.project_cosmos_db_operator,
  ]
  create_duration = "120s"
}

## Create connections
resource "azapi_resource" "storage_connection" {
  type      = "Microsoft.CognitiveServices/accounts/connections@2025-04-01-preview"
  name      = "storage-connection"
  parent_id = azapi_resource.ai_foundry.id

  body = {
    properties = {
      category      = "AzureStorageAccount"
      target        = local.storage_blob_endpoint
      authType      = "AAD"
      isSharedToAll = true
      metadata = {
        ApiType    = "Azure"
        ResourceId = local.storage_id
        location   = var.location
      }
    }
  }

  depends_on = [azapi_resource.ai_project]
}

resource "azapi_resource" "search_connection" {
  type      = "Microsoft.CognitiveServices/accounts/connections@2025-04-01-preview"
  name      = "search-connection"
  parent_id = azapi_resource.ai_foundry.id

  body = {
    properties = {
      category      = "CognitiveSearch"
      target        = "https://${local.search_name}.search.windows.net"
      authType      = "AAD"
      isSharedToAll = true
      metadata = {
        ApiType    = "Azure"
        ResourceId = local.search_id
        location   = var.location
      }
    }
  }

  depends_on = [azapi_resource.ai_project]
}

resource "azapi_resource" "cosmos_connection" {
  type      = "Microsoft.CognitiveServices/accounts/connections@2025-04-01-preview"
  name      = "cosmos-connection"
  parent_id = azapi_resource.ai_foundry.id

  body = {
    properties = {
      category      = "CosmosDB"
      target        = local.cosmos_endpoint
      authType      = "AAD"
      isSharedToAll = true
      metadata = {
        ApiType    = "Azure"
        ResourceId = local.cosmos_id
        location   = var.location
      }
    }
  }

  depends_on = [azapi_resource.ai_project]
}

## Wait for project + connections to settle before creating the capability host. The Foundry
## RP runs background "activation" after the project is created; PUTting the caphost too soon
## returns 409 "Unable to Update Service Container at this time. Activation is in progress".
resource "time_sleep" "wait_for_project_activation" {
  depends_on = [
    azapi_resource.ai_project,
    azapi_resource.storage_connection,
    azapi_resource.search_connection,
    azapi_resource.cosmos_connection,
    time_sleep.wait_for_project_rbac,
  ]
  create_duration = "180s"
}

## Create the ACCOUNT-level capability host first. The Foundry RP normally auto-creates one when
## the account is provisioned with allowProjectManagement = true, but on some accounts/regions it
## doesn't, and the project-level caphost PUT then fails with:
##   "Foundry Account capabilityHost Not Found, please retry again after creating capabilityHost
##    for the Foundry Account."
## Creating it explicitly here makes the deployment deterministic.
resource "azapi_resource" "account_capability_host" {
  type      = "Microsoft.CognitiveServices/accounts/capabilityHosts@2025-04-01-preview"
  name      = "${var.project_cap_host}-account"
  parent_id = azapi_resource.ai_foundry.id

  schema_validation_enabled = false

  body = {
    properties = {
      capabilityHostKind = "Agents"
      customerSubnet     = local.agent_subnet_id
    }
  }

  depends_on = [time_sleep.wait_for_project_activation]

  timeouts {
    create = "60m"
    update = "60m"
    delete = "60m"
  }
}

## Create the project-scoped capability host (kind = Agents). This is what wires the project's
## thread/storage/vector-store to the BYO Cosmos / Storage / AI Search connections and is required
## before any hosted-agent or thread-storage operations can succeed. Mirrors the Bicep module
## modules-network-secured/add-project-capability-host.bicep.
resource "azapi_resource" "project_capability_host" {
  type      = "Microsoft.CognitiveServices/accounts/projects/capabilityHosts@2025-04-01-preview"
  name      = var.project_cap_host
  parent_id = azapi_resource.ai_project.id

  # The azapi embedded schema for projects/capabilityHosts is currently incomplete and rejects
  # capabilityHostKind / *Connections properties at plan time. The Azure RP accepts them — disable
  # client-side schema validation so the body is sent through as-is.
  schema_validation_enabled = false

  body = {
    properties = {
      capabilityHostKind       = "Agents"
      vectorStoreConnections   = [azapi_resource.search_connection.name]
      storageConnections       = [azapi_resource.storage_connection.name]
      threadStorageConnections = [azapi_resource.cosmos_connection.name]
    }
  }

  depends_on = [azapi_resource.account_capability_host]

  timeouts {
    create = "60m"
    update = "60m"
    delete = "60m"
  }
}

## ---- Post-capability-host role assignments ----
## These MUST be created AFTER the capability host because they reference the workspace-scoped
## storage containers (<workspaceId>-azureml-agent) and the Cosmos `enterprise_memory` database
## that the caphost provisions. Mirrors the Bicep modules:
##   - modules-network-secured/blob-storage-container-role-assignments.bicep
##   - modules-network-secured/cosmos-container-role-assignments.bicep

resource "azurerm_role_assignment" "storage_blob_data_owner_project" {
  scope                = local.storage_id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = azapi_resource.ai_project.identity[0].principal_id
  principal_type       = "ServicePrincipal"

  condition_version = "2.0"
  condition         = "((!(ActionMatches{'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/tags/read'})  AND  !(ActionMatches{'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/filter/action'}) AND  !(ActionMatches{'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/tags/write'}) ) OR (@Resource[Microsoft.Storage/storageAccounts/blobServices/containers:name] StringStartsWithIgnoreCase '${local.project_workspace_id_guid}' AND @Resource[Microsoft.Storage/storageAccounts/blobServices/containers:name] StringLikeIgnoreCase '*-azureml-agent'))"

  depends_on = [azapi_resource.project_capability_host]
}

resource "azurerm_cosmosdb_sql_role_assignment" "cosmos_enterprise_memory_contributor" {
  resource_group_name = local.cosmos_rg
  account_name        = local.cosmos_name
  role_definition_id  = "${local.cosmos_id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  principal_id        = azapi_resource.ai_project.identity[0].principal_id
  scope               = "${local.cosmos_id}/dbs/enterprise_memory"

  depends_on = [azapi_resource.project_capability_host]
}

## Deploy model
resource "azapi_resource" "model_deployment" {
  type      = "Microsoft.CognitiveServices/accounts/deployments@2025-04-01-preview"
  name      = var.model_name
  parent_id = azapi_resource.ai_foundry.id

  body = {
    sku = {
      capacity = var.model_capacity
      name     = "GlobalStandard"
    }
    properties = {
      model = {
        name    = var.model_name
        format  = "OpenAI"
        version = var.model_version
      }
    }
  }

  depends_on = [azapi_resource.ai_project]
}

## Create APIM API for AI Foundry (only when creating APIM here — for BYO StandardV2 APIM the
## user manages their own API/policy definitions).
resource "azurerm_api_management_api" "ai_foundry_api" {
  count               = local.apim_create ? 1 : 0
  name                = "ai-foundry-api"
  resource_group_name = local.rg_name
  api_management_name = azurerm_api_management.apim[0].name
  revision            = "1"
  display_name        = "AI Foundry API"
  path                = "ai"
  protocols           = ["https"]
  service_url         = azapi_resource.ai_foundry.output.properties.endpoint

  depends_on = [azapi_resource.ai_foundry]
}
