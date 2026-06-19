data "azurerm_client_config" "current" {}

locals {
  ## Backend resource ID defaults
  cosmos_sub  = coalesce(var.cosmos_db_subscription_id, data.azurerm_client_config.current.subscription_id)
  storage_sub = coalesce(var.azure_storage_subscription_id, data.azurerm_client_config.current.subscription_id)
  search_sub  = coalesce(var.ai_search_subscription_id, data.azurerm_client_config.current.subscription_id)
  cosmos_rg   = coalesce(var.cosmos_db_resource_group_name, var.resource_group_name)
  storage_rg  = coalesce(var.azure_storage_resource_group_name, var.resource_group_name)
  search_rg   = coalesce(var.ai_search_resource_group_name, var.resource_group_name)

  account_id        = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${var.resource_group_name}/providers/Microsoft.CognitiveServices/accounts/${var.account_name}"
  source_project_id = "${local.account_id}/projects/${var.source_project_name}"

  cosmos_id  = "/subscriptions/${local.cosmos_sub}/resourceGroups/${local.cosmos_rg}/providers/Microsoft.DocumentDB/databaseAccounts/${var.cosmos_db_account_name}"
  storage_id = "/subscriptions/${local.storage_sub}/resourceGroups/${local.storage_rg}/providers/Microsoft.Storage/storageAccounts/${var.azure_storage_account_name}"
  search_id  = "/subscriptions/${local.search_sub}/resourceGroups/${local.search_rg}/providers/Microsoft.Search/searchServices/${var.ai_search_service_name}"

  ## Per-project derived names (account-unique)
  target_cosmos_conn  = { for p in var.target_project_names : p => "${var.cosmos_db_connection}-${p}" }
  target_storage_conn = { for p in var.target_project_names : p => "${var.azure_storage_connection}-${p}" }
  target_search_conn  = { for p in var.target_project_names : p => "${var.ai_search_connection}-${p}" }
}

############################################################
## Read source connections (full body) to mirror onto each target
############################################################
data "azapi_resource" "src_cosmos" {
  type                   = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  resource_id            = "${local.source_project_id}/connections/${var.cosmos_db_connection}"
  response_export_values = ["properties"]
}

data "azapi_resource" "src_storage" {
  type                   = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  resource_id            = "${local.source_project_id}/connections/${var.azure_storage_connection}"
  response_export_values = ["properties"]
}

data "azapi_resource" "src_search" {
  type                   = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  resource_id            = "${local.source_project_id}/connections/${var.ai_search_connection}"
  response_export_values = ["properties"]
}

############################################################
## Target projects (one per name) ##
############################################################
resource "azapi_resource" "target_project" {
  for_each = toset(var.target_project_names)

  type      = "Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview"
  name      = each.key
  location  = var.location
  parent_id = local.account_id

  identity {
    type = "SystemAssigned"
  }

  body = {
    properties = {}
  }

  response_export_values = ["identity.principalId", "properties.internalId"]
}

############################################################
## Per-project workspace ID (formatted as a GUID)
############################################################
locals {
  workspace_id_guid = {
    for p, proj in azapi_resource.target_project :
    p => format(
      "%s-%s-%s-%s-%s",
      substr(proj.output.properties.internalId, 0, 8),
      substr(proj.output.properties.internalId, 8, 4),
      substr(proj.output.properties.internalId, 12, 4),
      substr(proj.output.properties.internalId, 16, 4),
      substr(proj.output.properties.internalId, 20, 12),
    )
  }
}

############################################################
## Clone connections onto each target project
############################################################
resource "azapi_resource" "clone_cosmos" {
  for_each = toset(var.target_project_names)

  type      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  name      = local.target_cosmos_conn[each.key]
  parent_id = azapi_resource.target_project[each.key].id

  schema_validation_enabled = false

  body = {
    properties = {
      category      = data.azapi_resource.src_cosmos.output.properties.category
      target        = data.azapi_resource.src_cosmos.output.properties.target
      authType      = data.azapi_resource.src_cosmos.output.properties.authType
      isSharedToAll = data.azapi_resource.src_cosmos.output.properties.isSharedToAll
      metadata      = data.azapi_resource.src_cosmos.output.properties.metadata
    }
  }
}

resource "azapi_resource" "clone_storage" {
  for_each = toset(var.target_project_names)

  type      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  name      = local.target_storage_conn[each.key]
  parent_id = azapi_resource.target_project[each.key].id

  schema_validation_enabled = false

  body = {
    properties = {
      category      = data.azapi_resource.src_storage.output.properties.category
      target        = data.azapi_resource.src_storage.output.properties.target
      authType      = data.azapi_resource.src_storage.output.properties.authType
      isSharedToAll = data.azapi_resource.src_storage.output.properties.isSharedToAll
      metadata      = data.azapi_resource.src_storage.output.properties.metadata
    }
  }
}

resource "azapi_resource" "clone_search" {
  for_each = toset(var.target_project_names)

  type      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  name      = local.target_search_conn[each.key]
  parent_id = azapi_resource.target_project[each.key].id

  schema_validation_enabled = false

  body = {
    properties = {
      category      = data.azapi_resource.src_search.output.properties.category
      target        = data.azapi_resource.src_search.output.properties.target
      authType      = data.azapi_resource.src_search.output.properties.authType
      isSharedToAll = data.azapi_resource.src_search.output.properties.isSharedToAll
      metadata      = data.azapi_resource.src_search.output.properties.metadata
    }
  }
}

############################################################
## Pre-capHost RBAC (one assignment per project per backend)
############################################################
resource "azurerm_role_assignment" "storage_blob_data_contributor" {
  for_each = toset(var.target_project_names)

  scope                = local.storage_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azapi_resource.target_project[each.key].output.identity.principalId
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "cosmos_db_operator" {
  for_each = toset(var.target_project_names)

  scope                = local.cosmos_id
  role_definition_name = "Cosmos DB Operator"
  principal_id         = azapi_resource.target_project[each.key].output.identity.principalId
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "search_index_data_contributor" {
  for_each = toset(var.target_project_names)

  scope                = local.search_id
  role_definition_name = "Search Index Data Contributor"
  principal_id         = azapi_resource.target_project[each.key].output.identity.principalId
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "search_service_contributor" {
  for_each = toset(var.target_project_names)

  scope                = local.search_id
  role_definition_name = "Search Service Contributor"
  principal_id         = azapi_resource.target_project[each.key].output.identity.principalId
  principal_type       = "ServicePrincipal"
}

############################################################
## Project capability host (Agents) — one per project
############################################################
resource "azapi_resource" "cap_host" {
  for_each = toset(var.target_project_names)

  type      = "Microsoft.CognitiveServices/accounts/projects/capabilityHosts@2025-04-01-preview"
  name      = var.project_cap_host
  parent_id = azapi_resource.target_project[each.key].id

  # capabilityHostKind is accepted by the API but missing from the published azapi schema.
  schema_validation_enabled = false

  body = {
    properties = {
      capabilityHostKind       = "Agents"
      threadStorageConnections = [local.target_cosmos_conn[each.key]]
      storageConnections       = [local.target_storage_conn[each.key]]
      vectorStoreConnections   = [local.target_search_conn[each.key]]
    }
  }

  depends_on = [
    azapi_resource.clone_cosmos,
    azapi_resource.clone_storage,
    azapi_resource.clone_search,
    azurerm_role_assignment.storage_blob_data_contributor,
    azurerm_role_assignment.cosmos_db_operator,
    azurerm_role_assignment.search_index_data_contributor,
    azurerm_role_assignment.search_service_contributor,
  ]
}

############################################################
## Post-capHost ABAC-scoped role assignments (per project)
############################################################
resource "azurerm_role_assignment" "storage_blob_data_owner_scoped" {
  for_each = toset(var.target_project_names)

  scope                = local.storage_id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = azapi_resource.target_project[each.key].output.identity.principalId
  principal_type       = "ServicePrincipal"
  condition_version    = "2.0"
  condition            = <<-EOT
    ((!(ActionMatches{'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/tags/read'})  AND  !(ActionMatches{'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/filter/action'}) AND  !(ActionMatches{'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/tags/write'}) ) OR (@Resource[Microsoft.Storage/storageAccounts/blobServices/containers:name] StringStartsWithIgnoreCase '${local.workspace_id_guid[each.key]}' AND @Resource[Microsoft.Storage/storageAccounts/blobServices/containers:name] StringLikeIgnoreCase '*-azureml-agent'))
  EOT

  depends_on = [azapi_resource.cap_host]
}

resource "azurerm_cosmosdb_sql_role_assignment" "cosmos_data_contributor_scoped" {
  for_each = toset(var.target_project_names)

  resource_group_name = local.cosmos_rg
  account_name        = var.cosmos_db_account_name
  role_definition_id  = "${local.cosmos_id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  principal_id        = azapi_resource.target_project[each.key].output.identity.principalId
  scope               = "${local.cosmos_id}/dbs/enterprise_memory"

  depends_on = [
    azapi_resource.cap_host,
    azurerm_role_assignment.storage_blob_data_owner_scoped,
  ]
}
