output "project_cap_host_name" {
  description = "Name of the project capability host"
  value       = azapi_resource.cap_host.name
}

output "cloned_connections" {
  description = "Names of the cloned connections on the target project"
  value = {
    cosmos_db     = azapi_resource.clone_cosmos.name
    azure_storage = azapi_resource.clone_storage.name
    ai_search     = azapi_resource.clone_search.name
  }
}

output "target_project_principal_id" {
  description = "System-assigned managed identity principal ID of the target project"
  value       = azapi_resource.target_project.output.identity.principalId
}

output "target_project_workspace_id_guid" {
  description = "Formatted GUID of the target project's internal workspace ID"
  value       = local.workspace_id_guid
}
