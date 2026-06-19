output "project_cap_host_names" {
  description = "Capability host names per target project"
  value       = { for p, h in azapi_resource.cap_host : p => h.name }
}

output "cloned_connections" {
  description = "Cloned connection names per target project"
  value = {
    for p in var.target_project_names : p => {
      cosmos_db     = azapi_resource.clone_cosmos[p].name
      azure_storage = azapi_resource.clone_storage[p].name
      ai_search     = azapi_resource.clone_search[p].name
    }
  }
}

output "target_project_principal_ids" {
  description = "System-assigned managed identity principal IDs per target project"
  value       = { for p, proj in azapi_resource.target_project : p => proj.output.identity.principalId }
}

output "target_project_workspace_id_guids" {
  description = "Formatted GUID of each target project's internal workspace ID"
  value       = local.workspace_id_guid
}
