## -------- Foundry account + projects --------
variable "resource_group_name" {
  description = "Resource group containing the Foundry (Cognitive Services) account"
  type        = string
}

variable "account_name" {
  description = "Foundry (Cognitive Services) account name"
  type        = string
}

variable "source_project_name" {
  description = "Existing project that already has the three BYO connections (source for the clone)"
  type        = string
}

variable "target_project_names" {
  description = "Set of new project names. Each gets cloned connections + a capability host. Add to this set to onboard more projects in the same apply."
  type        = set(string)

  validation {
    condition     = length(var.target_project_names) > 0
    error_message = "Provide at least one target project name."
  }
}

variable "location" {
  description = "Azure region for the new target projects. Must match the parent Foundry account's region."
  type        = string
}

## -------- Source connection names --------
variable "cosmos_db_connection" {
  description = "Connection name on the source project pointing to Cosmos DB (thread storage)"
  type        = string
}

variable "azure_storage_connection" {
  description = "Connection name on the source project pointing to Storage account (blob)"
  type        = string
}

variable "ai_search_connection" {
  description = "Connection name on the source project pointing to AI Search (vector store)"
  type        = string
}

## -------- Capability host --------
variable "project_cap_host" {
  description = "Project capability host name (same value used on each target project)"
  type        = string
  default     = "caphostproj"
}

## -------- Underlying backend resources (for RBAC scope) --------
variable "cosmos_db_account_name" {
  description = "Cosmos DB account name (underlying resource pointed to by the connection)"
  type        = string
}

variable "azure_storage_account_name" {
  description = "Storage account name (underlying resource pointed to by the connection)"
  type        = string
}

variable "ai_search_service_name" {
  description = "AI Search service name (underlying resource pointed to by the connection)"
  type        = string
}

variable "cosmos_db_resource_group_name" {
  description = "Resource group of the Cosmos DB account. Defaults to var.resource_group_name."
  type        = string
  default     = null
}

variable "azure_storage_resource_group_name" {
  description = "Resource group of the Storage account. Defaults to var.resource_group_name."
  type        = string
  default     = null
}

variable "ai_search_resource_group_name" {
  description = "Resource group of the AI Search service. Defaults to var.resource_group_name."
  type        = string
  default     = null
}

variable "cosmos_db_subscription_id" {
  description = "Subscription ID of the Cosmos DB account. Defaults to current."
  type        = string
  default     = null
}

variable "azure_storage_subscription_id" {
  description = "Subscription ID of the Storage account. Defaults to current."
  type        = string
  default     = null
}

variable "ai_search_subscription_id" {
  description = "Subscription ID of the AI Search service. Defaults to current."
  type        = string
  default     = null
}
