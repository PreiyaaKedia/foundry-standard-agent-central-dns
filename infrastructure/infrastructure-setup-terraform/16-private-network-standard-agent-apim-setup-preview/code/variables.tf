variable "location" {
  description = "The Azure region where resources will be deployed"
  type        = string
  default     = "eastus2"
}

variable "ai_services_name_prefix" {
  description = "Prefix for AI Foundry account name"
  type        = string
  default     = "foundry"
}

variable "project_name" {
  description = "The name of the project"
  type        = string
  default     = "private-apim-agent-project"
}

variable "project_cap_host" {
  description = "Name of the project-scoped capability host (kind = Agents). Mirrors the Bicep `projectCapHost` parameter."
  type        = string
  default     = "caphostproj"
}

variable "vnet_address_space" {
  description = "Address space for the virtual network"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "subnet_private_endpoints_prefix" {
  description = "Address prefix for private endpoints subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "subnet_apim_prefix" {
  description = "Address prefix for APIM subnet. Only used when apim_mode = create-internal."
  type        = string
  default     = "10.0.2.0/24"
}

variable "apim_mode" {
  description = <<-EOT
    How APIM is wired into this deployment.

    - "create-internal" (default): the template creates a new APIM in Internal VNet mode using the
      apim_sku / apim_publisher_* / subnet_apim_prefix variables. No APIM private endpoint is
      created (Internal mode doesn't use one).
    - "byo-standardv2": the template does NOT create APIM, subnet_apim, or the APIM NSG. Instead
      it creates a Gateway private endpoint pointing at the existing StandardV2 APIM specified by
      existing_apim_id, and registers it in privatelink.azure-api.net (locally or via central DNS,
      depending on existing_dns_zones). existing_apim_gateway_url is used as the Foundry-side
      connection target.
  EOT
  type        = string
  default     = "create-internal"
  validation {
    condition     = contains(["create-internal", "byo-standardv2"], var.apim_mode)
    error_message = "apim_mode must be one of: create-internal, byo-standardv2."
  }
}

variable "existing_apim_id" {
  description = "Required when apim_mode = byo-standardv2. Full ARM resource ID of the existing StandardV2 APIM (may live in a different resource group or subscription)."
  type        = string
  default     = ""
}

variable "existing_apim_gateway_url" {
  description = "Required when apim_mode = byo-standardv2. The gateway URL of the existing APIM (e.g. https://<name>.azure-api.net). Used as the target of the Foundry APIM connection / API service URL."
  type        = string
  default     = ""
}

variable "create_apim_pe" {
  description = <<-EOT
    Only used when apim_mode = byo-standardv2.

    - true (default): create a Gateway private endpoint for the existing APIM into the spoke PE
      subnet and auto-register its A record in privatelink.azure-api.net (or central DNS, per
      existing_dns_zones).
    - false: skip both the PE and DNS A-record registration. Use this when the spoke VNet can
      already reach the APIM privately via a pre-existing PE you manage yourself (e.g. shared in
      the hub, or already deployed into this same VNet). You are responsible for ensuring DNS
      resolution of <apim>.azure-api.net from the spoke.
  EOT
  type        = bool
  default     = true
}

variable "apim_sku" {
  description = "SKU for API Management (Developer, Standard, Premium). Only used when apim_mode = create-internal."
  type        = string
  default     = "Developer"
  validation {
    condition     = contains(["Developer", "Standard", "Premium"], var.apim_sku)
    error_message = "APIM SKU must be Developer, Standard, or Premium for VNet integration"
  }
}

variable "apim_publisher_name" {
  description = "Publisher name for API Management. Only used when apim_mode = create-internal."
  type        = string
  default     = "AI Foundry Publisher"
}

variable "apim_publisher_email" {
  description = "Publisher email for API Management. Only used when apim_mode = create-internal."
  type        = string
  default     = "admin@example.com"
}

variable "model_name" {
  description = "The model to deploy"
  type        = string
  default     = "gpt-4.1"
}

variable "model_version" {
  description = "The version of the model"
  type        = string
  default     = "2025-04-14"
}

variable "model_capacity" {
  description = "The capacity of the model deployment"
  type        = number
  default     = 40
}

variable "existing_dns_zones" {
  description = <<-EOT
    Optional. Map of private DNS zone FQDN to its location.
    Each value is an object { subscription_id, resource_group_name }.

    - If resource_group_name is empty (default), the zone is CREATED locally in this deployment's
      resource group and a VNet link is created automatically.
    - If resource_group_name is set, the existing zone is REFERENCED. No zone and no VNet link are
      created by this template — the hub/central-DNS team must pre-create the VNet link from the
      zone to this VNet, and the deploying identity needs "Private DNS Zone Contributor" on the
      central DNS resource group so the private endpoint can register its A-record.
    - subscription_id may be empty to default to the deployment subscription, or set to a different
      subscription for central/hub DNS scenarios.

    Supported zone keys (must match exactly):
      privatelink.services.ai.azure.com         (Foundry account PE)
      privatelink.openai.azure.com              (Foundry account PE)
      privatelink.cognitiveservices.azure.com   (Foundry account PE)
      privatelink.blob.core.windows.net
      privatelink.search.windows.net
      privatelink.documents.azure.com
      privatelink.azure-api.net                 (APIM; this template has no APIM PE — manual A-record needed for local mode)
  EOT
  type = map(object({
    subscription_id     = optional(string, "")
    resource_group_name = optional(string, "")
  }))
  default = {
    "privatelink.services.ai.azure.com"       = { subscription_id = "", resource_group_name = "" }
    "privatelink.openai.azure.com"            = { subscription_id = "", resource_group_name = "" }
    "privatelink.cognitiveservices.azure.com" = { subscription_id = "", resource_group_name = "" }
    "privatelink.blob.core.windows.net"       = { subscription_id = "", resource_group_name = "" }
    "privatelink.search.windows.net"          = { subscription_id = "", resource_group_name = "" }
    "privatelink.documents.azure.com"         = { subscription_id = "", resource_group_name = "" }
    "privatelink.azure-api.net"               = { subscription_id = "", resource_group_name = "" }
  }
}

# ---- BYO shared resources ----
# For each shared resource (RG, VNet, Storage, AI Search, Cosmos), set the matching variable to
# reference an existing resource instead of creating a new one. When unset (""), the template
# creates that resource. Private endpoints into the spoke VNet are always created against the
# resolved resource (Bicep parity).

variable "existing_resource_group_name" {
  description = "Optional. Name of an existing resource group (in the deployment subscription) to deploy into. If empty, the template creates rg-aifoundry<rand>."
  type        = string
  default     = ""
}

variable "existing_vnet_id" {
  description = "Optional. Full ARM resource ID of an existing Virtual Network (may live in a different RG or subscription). If empty, the template creates a new VNet. Requires existing_pe_subnet_name (and existing_apim_subnet_name if apim_mode = create-internal)."
  type        = string
  default     = ""
}

variable "existing_pe_subnet_name" {
  description = "Required when existing_vnet_id is set. Name of the subnet within the existing VNet that will host all private endpoints created by this template."
  type        = string
  default     = ""
}

variable "existing_agent_subnet_name" {
  description = "Required when existing_vnet_id is set. Name of the subnet within the existing VNet that the Foundry agent runtime is injected into (networkInjections, scenario=agent). Must be a separate subnet from existing_pe_subnet_name; this template will add a Microsoft.App/environments delegation to it."
  type        = string
  default     = ""
}

variable "existing_apim_subnet_name" {
  description = "Required when existing_vnet_id is set AND apim_mode = create-internal. Name of the dedicated APIM subnet (delegated/sized per APIM requirements) within the existing VNet."
  type        = string
  default     = ""
}

variable "existing_storage_account_id" {
  description = "Optional. Full ARM resource ID of an existing Storage Account (cross-sub supported). If empty, the template creates one."
  type        = string
  default     = ""
}

variable "existing_ai_search_id" {
  description = "Optional. Full ARM resource ID of an existing AI Search service (cross-sub supported). If empty, the template creates one."
  type        = string
  default     = ""
}

variable "existing_cosmos_db_account_id" {
  description = "Optional. Full ARM resource ID of an existing Cosmos DB account (cross-sub supported). If empty, the template creates one."
  type        = string
  default     = ""
}

# ---- Name overrides for resources this template CREATES ----
# Used only when the corresponding existing_*_id is empty (i.e. this template creates the resource).
# Leave as "" to fall back to the auto-generated name (aifoundry<rand>...). Storage account names
# must be globally unique, 3-24 chars, lowercase letters/numbers only.

variable "storage_account_name" {
  description = "Optional. Name for the storage account this template creates. Ignored when existing_storage_account_id is set. Defaults to aifoundry<rand>stor."
  type        = string
  default     = ""
}

variable "ai_search_name" {
  description = "Optional. Name for the AI Search service this template creates. Ignored when existing_ai_search_id is set. Defaults to aifoundry-<rand>-search."
  type        = string
  default     = ""
}

variable "cosmos_db_account_name" {
  description = "Optional. Name for the Cosmos DB account this template creates. Ignored when existing_cosmos_db_account_id is set. Defaults to aifoundry<rand>cosmos."
  type        = string
  default     = ""
}
