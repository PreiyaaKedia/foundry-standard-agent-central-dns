# Clone Project Connections + Attach Capability Host

Terraform equivalent of [`clone-connections-and-caphost.bicep`](../../../../infrastructure-setup-bicep/16-private-network-standard-agent-apim-setup/modules-network-secured/clone-connections-and-caphost.bicep).

Use this against an **existing** Foundry account where one project already has the three BYO connections (Cosmos DB, Storage, AI Search) wired up and you want to add another project that shares the same backends. The new project is created by this module.

## What it does

1. Creates a new project (`target_project_name`) under the existing Foundry account with a system-assigned managed identity.
2. Reads the three source-project connections (`cosmosDBConnection`, `azureStorageConnection`, `aiSearchConnection`).
3. Clones them onto the new project under unique names (`<src>-<targetProject>` by default).
4. Grants the new project's managed identity five pre-capHost roles on the shared backends:
   - Storage Blob Data Contributor (storage account)
   - Cosmos DB Operator (cosmos account)
   - Search Index Data Contributor + Search Service Contributor (search service)
5. Creates the project `capabilityHosts/<name>` (kind `Agents`). The account-level capability host (with `customerSubnet`) must already exist on the account — typically created by the main template — and the new project inherits its networkInjection subnet automatically.
6. Grants two post-capHost ABAC-scoped roles:
   - Storage Blob Data Owner — scoped to containers `<workspaceId>-*-azureml-agent`
   - Cosmos SQL Built-in Data Contributor — scoped to the `enterprise_memory` database

## Usage

```hcl
terraform init
terraform apply -var-file=terraform.tfvars
```

See [`terraform.tfvars.example`](./terraform.tfvars.example) for the full input set.

## Notes

- The `target_project_name` must NOT already exist under the account — this module creates it. Set `location` to match the parent account's region.
- Connection names are **unique per account** (not per project) — that's why the clones get a `-<targetProject>` suffix. Override `target_*_connection` to customize.
- The Cosmos DB account must already have a SQL database named `enterprise_memory` (the standard agent setup creates this on first capHost).
- If the three backends live in a different resource group or subscription than the Foundry account, pass `*_resource_group_name` / `*_subscription_id`.
