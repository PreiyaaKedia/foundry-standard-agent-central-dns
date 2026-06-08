# Account-Level vs Project-Level APIM Connections

## Background

The original APIM connection Bicep only created **project-scoped** connections (`Microsoft.CognitiveServices/accounts/projects/connections`). For customers who run **multiple Foundry projects under a single Foundry account** and want one shared APIM connection that:

- is usable by every project in the account, and
- survives deletion of any individual project,

a project-scoped connection isn't sufficient. Setting `isSharedToAll: true` on a project-scoped connection only widens *read* access — the connection is still owned by one project and is deleted when that project is deleted.

The template now supports **account-scoped** connections (`Microsoft.CognitiveServices/accounts/connections`) as an opt-in alongside the existing project-scoped behavior.

## What changed

| Concept | Project scope (existing) | Account scope (new) |
|---|---|---|
| Resource type | `Microsoft.CognitiveServices/accounts/projects/connections` | `Microsoft.CognitiveServices/accounts/connections` |
| Parent resource | A Foundry project | The Foundry account |
| Required ID parameter | `projectResourceId` | `accountResourceId` |
| Visible to other projects | Only if `isSharedToAll = true` | Always (account-owned) |
| Survives project deletion | No | Yes |
| Deleted with | Project | Account |

A new parameter `connectionScope` selects the path. Default is `project` so all existing parameter files continue to work unchanged.

## Parameter changes

### `connection-apim.bicep`

New parameters:

```bicep
@allowed(['project', 'account'])
@description('Scope at which the connection is created. "project" (default) creates it under a Foundry project. "account" creates it under the Foundry account so all projects in the account can use it and the connection survives project deletion.')
param connectionScope string = 'project'

@description('Resource ID of the AI Foundry project. Required when connectionScope = "project".')
param projectResourceId string = '...'

@description('Resource ID of the AI Foundry account. Required when connectionScope = "account".')
param accountResourceId string = ''
```

A validation block fails the deployment with a clear message when `connectionScope = 'account'` and `accountResourceId` is empty.

### `modules/apim-connection-common.bicep`

The module now declares **four** connection resources, gated by `(connectionScope, authType)`:

| Scope | AuthType | Resource declaration |
|---|---|---|
| `project` | `ApiKey` | `connectionApiKeyProject` (existing behavior) |
| `project` | `ProjectManagedIdentity` | `connectionAADProject` (existing behavior) |
| `account` | `ApiKey` | `connectionApiKeyAccount` (new) |
| `account` | `ProjectManagedIdentity` | `connectionAADAccount` (new, `isSharedToAll` forced to `true`) |

Account-scope connections set `parent: aiFoundry` instead of `parent: aiProject`. The project resource is only resolved when scope is `project`.

### Sample parameter files

All four samples now expose `connectionScope` + `accountResourceId`:

- [parameters-dynamic-discovery.json](samples/parameters-dynamic-discovery.json)
- [parameters-static-models.json](samples/parameters-static-models.json)
- [parameters-custom-auth-config.json](samples/parameters-custom-auth-config.json)
- [parameters-custom-headers.json](samples/parameters-custom-headers.json)

An account-scoped example is also included:
- [parameters-dynamic-discovery_v1.json](samples/parameters-dynamic-discovery_v1.json)

## How to use

### Project-scoped connection (default — no change for existing users)

```jsonc
{
  "parameters": {
    "connectionScope":   { "value": "project" },
    "projectResourceId": { "value": "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.CognitiveServices/accounts/<foundry>/projects/<project>" },
    "accountResourceId": { "value": "" },
    "apimResourceId":    { "value": "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.ApiManagement/service/<apim>" },
    // ...rest unchanged
  }
}
```

### Account-scoped connection (new)

```jsonc
{
  "parameters": {
    "connectionScope":   { "value": "account" },
    "projectResourceId": { "value": "" },
    "accountResourceId": { "value": "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.CognitiveServices/accounts/<foundry>" },
    "apimResourceId":    { "value": "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.ApiManagement/service/<apim>" },
    "connectionName":    { "value": "apim-foundry-shared" },
    "authType":          { "value": "ApiKey" },
    // isSharedToAll is auto-forced to true at account scope; param is ignored
    // ...rest of metadata fields the same as project scope
  }
}
```

Deploy with the same command — no change:

```powershell
az deployment group create `
  --resource-group <rg-of-foundry-account> `
  --template-file connection-apim.bicep `
  --parameters samples/parameters-dynamic-discovery_v1.json
```

## When to use which

**Use project scope when:**
- The connection is intended for a single project's use.
- You want connection lifecycle to be tied to the project.
- Different projects need different APIM endpoints / credentials.

**Use account scope when:**
- Multiple projects in the same Foundry account share a single APIM gateway.
- The connection must survive project deletion / recreation.
- You want one place to rotate the APIM key / update metadata for all projects.

## Things to validate before production rollout

1. **AuthType support at account scope** — confirm with engineering that `Microsoft.CognitiveServices/accounts/connections@2025-04-01-preview` accepts both `ApiKey` and `ProjectManagedIdentity`. If only one is supported, drop the other branch.
2. **Recompile JSON** — both `connection-apim.json` and `modules/apim-connection-common.json` must be rebuilt whenever the `.bicep` files change:
   ```powershell
   az bicep build --file .\connection-apim.bicep
   az bicep build --file .\modules\apim-connection-common.bicep
   ```
3. **Cross-project smoke test** — deploy an agent in two different projects within the same account and verify both can resolve the account-scoped connection by name.
4. **Deletion semantics** — document for the customer that an account-scoped connection is removed when the **account** is deleted/purged. Folds into the standard-agent cleanup playbook.

## Backward compatibility

This change is **additive**:

- Default value of `connectionScope` is `project`.
- Existing parameter files that don't set `connectionScope` continue to deploy project-scoped connections with identical behavior.
- No breaking change to outputs (`connectionName`, `connectionId`, `targetUrl`, `authType`, `metadata`); a new output `connectionScope` is added.
