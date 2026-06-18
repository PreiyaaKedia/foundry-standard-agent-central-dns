output "resource_group_name" {
  description = "The name of the resource group (created here or BYO)."
  value       = local.rg_name
}

output "vnet_id" {
  description = "The ID of the virtual network (created here or BYO)."
  value       = local.vnet_id
}

output "ai_foundry_id" {
  description = "The ID of the AI Foundry account"
  value       = azapi_resource.ai_foundry.id
}

output "ai_project_id" {
  description = "The ID of the AI Foundry project"
  value       = azapi_resource.ai_project.id
}

output "storage_account_id" {
  description = "The ID of the storage account (created here or BYO)."
  value       = local.storage_id
}

output "search_service_id" {
  description = "The ID of the AI Search service (created here or BYO)."
  value       = local.search_id
}

output "cosmos_db_id" {
  description = "The ID of the Cosmos DB account (created here or BYO)."
  value       = local.cosmos_id
}

output "apim_id" {
  description = "The ID of the API Management instance (created here or BYO)."
  value       = var.apim_mode == "create-internal" ? azurerm_api_management.apim[0].id : var.existing_apim_id
}

output "apim_gateway_url" {
  description = "The gateway URL of the API Management instance (created here or BYO)."
  value       = var.apim_mode == "create-internal" ? azurerm_api_management.apim[0].gateway_url : var.existing_apim_gateway_url
}

output "apim_portal_url" {
  description = "The portal URL of the API Management instance. Empty in BYO mode (managed by the APIM owner)."
  value       = var.apim_mode == "create-internal" ? azurerm_api_management.apim[0].portal_url : ""
}

output "notes" {
  description = "Important notes about this deployment"
  value       = "This is a complex scenario. Additional APIM API configuration, policies, and subscriptions need to be configured manually or via additional Terraform resources."
}
