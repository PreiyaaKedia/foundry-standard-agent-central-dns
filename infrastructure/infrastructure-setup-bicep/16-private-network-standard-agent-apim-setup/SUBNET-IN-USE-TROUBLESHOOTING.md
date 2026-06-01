# Troubleshooting: "Subnet already in use" on Redeploy

## Symptom

Redeploy of this template fails with:

```
Code: ResourceDeploymentFailure
Kind: AmlRp, Code: BadRequest
Message: Capability host creation failed with agent messages:
  "The subnet '/subscriptions/.../virtualNetworks/<vnet>/subnets/<agent-subnet>'
   is already in use. The subnet must not already be in use by any other
   environment or Azure service."
```

## Root Cause

The agent subnet is delegated exclusively to `Microsoft.App/environments` and can hold a `serviceAssociationLink` for only one Foundry **capability host (caphost)** at a time.

- Deleting the Foundry **project** does **not** release the subnet — the **account-level caphost** still owns the link.
- Deleting the Foundry **account** does **not** release the subnet either — Cognitive Services accounts are **soft-deleted** by default, and the caphost (and subnet link) survive until the account is **purged**.

The subnet is freed only after the account-level caphost is explicitly deleted, **or** the soft-deleted account is purged.

---

## Decision Tree

Run these first to know which path applies:

```powershell
# Is the account live?
az cognitiveservices account show --name <account-name> --resource-group <rg> --query "name" -o tsv 2>$null

# Is the account soft-deleted?
az cognitiveservices account list-deleted --query "[?name=='<account-name>'].{name:name, location:location, deletionDate:properties.deletionDate}"
```

| `account show` | `list-deleted` | Path |
|----------------|----------------|------|
| Returns the name | n/a | **Path A** — Delete caphost via script |
| Not found | Returns the account | **Path B** — Purge the soft-deleted account |
| Not found | Empty | **Path C** — Wait for backend cleanup / open support ticket |

---

## Path A — Account is live, delete the caphost

Use this when the Foundry account still exists (project may already be deleted — that's fine).

### Step 1 — List capability hosts on the account

```powershell
$SUB_ID = az account show --query id -o tsv
$RG = "<your-foundry-rg>"
$ACCOUNT = "<your-foundry-account>"

az rest --method GET --url "https://management.azure.com/subscriptions/$SUB_ID/resourceGroups/$RG/providers/Microsoft.CognitiveServices/accounts/$ACCOUNT/capabilityHosts?api-version=2025-04-01-preview"
```

Note the `name` of the caphost (e.g. `caphost1`).

> ⚠️ Do **not** use `az cognitiveservices account show --query "properties.allowProjectManagement"` to check for a caphost — that property is unrelated and is often empty/null. Capability hosts are sub-resources and must be queried via the REST endpoint above.

### Step 2 — Check for any remaining project caphosts (must be deleted first)

```powershell
# List projects on the account
az rest --method GET --url "https://management.azure.com/subscriptions/$SUB_ID/resourceGroups/$RG/providers/Microsoft.CognitiveServices/accounts/$ACCOUNT/projects?api-version=2025-04-01-preview"
```

For each project listed, list its caphosts:

```powershell
az rest --method GET --url "https://management.azure.com/subscriptions/$SUB_ID/resourceGroups/$RG/providers/Microsoft.CognitiveServices/accounts/$ACCOUNT/projects/<projectName>/capabilityHosts?api-version=2025-04-01-preview"
```

If any project caphosts exist, delete them first by running `deleteCapHost.sh` and providing the **project name** when prompted (instead of the account name).

### Step 3 — Run `deleteCapHost.sh` against the account caphost

From this folder (use WSL or Git Bash on Windows — requires `bash`, `curl`, `jq`, `az`):

```bash
chmod +x deleteCapHost.sh
./deleteCapHost.sh
```

Provide when prompted:

| Prompt | Value |
|--------|-------|
| Subscription ID | your subscription ID |
| Resource Group name | resource group of the Foundry account |
| Foundry Account or Project name | **account** name (from Step 1) |
| CapabilityHost name | caphost `name` from Step 1 (e.g. `caphost1`) |

Wait for `Capability host deletion completed successfully.`

### Step 4 — Wait for subnet unlink, then redeploy

See **[Verify the subnet is free](#verify-the-subnet-is-free)** below, then redeploy.

---

## Path B — Account is soft-deleted, purge it

Purging triggers the backend to delete the caphost and release the subnet automatically. This is the **only** path that works once the account is gone — `deleteCapHost.sh` cannot delete a caphost when the parent account no longer exists (the DELETE will return 404).

### Step 1 — Get the location of the soft-deleted account

```powershell
az cognitiveservices account list-deleted --query "[?name=='<account-name>'].{name:name, location:location, resourceGroup:resourceGroup, deletionDate:properties.deletionDate}"
```

### Step 2 — Purge

```powershell
az cognitiveservices account purge `
  --location <location-from-step-1> `
  --resource-group <rg-from-step-1> `
  --name <account-name>
```

Reference: [Recover or purge deleted Azure AI services resources](https://learn.microsoft.com/azure/ai-services/recover-purge-resources?tabs=azure-portal#purge-a-deleted-resource).

### Step 3 — Wait for subnet unlink, then redeploy

See **[Verify the subnet is free](#verify-the-subnet-is-free)** below.

---

## Path C — Account is fully gone but subnet is still locked

If `account show` returns not-found **and** `account list-deleted` is empty, the backend cleanup of the caphost / subnet link is still in flight.

1. Wait — typically up to ~20 minutes, occasionally longer.
2. Poll the subnet (see below).
3. If `serviceAssociationLinks` is still populated after ~1 hour, open an Azure support ticket. Only the platform can force-clear a stuck `serviceAssociationLink` at that point.

---

## Verify the subnet is free

After running Path A, B, or while waiting in Path C, poll the subnet until `serviceAssociationLinks` is empty:

```powershell
az network vnet subnet show `
  --ids "/subscriptions/<vnet-sub>/resourceGroups/<vnet-rg>/providers/Microsoft.Network/virtualNetworks/<vnet>/subnets/<agent-subnet>" `
  --query "{serviceAssociationLinks: serviceAssociationLinks, ipConfigurations: ipConfigurations, delegations: delegations[].serviceName}"
```

Ready to reuse when:

- `serviceAssociationLinks` is `null` or `[]`
- `ipConfigurations` is `null` or `[]`
- `delegations` still shows `Microsoft.App/environments` (expected and required)

Backend unlink is asynchronous — allow up to ~20 minutes even after Path A or B reports success.

## Redeploy

```powershell
az deployment group create `
  --resource-group <rg> `
  --template-file main.bicep `
  --parameters main.bicepparam
```

---

## Alternative: Deploy to a different subnet

If you can't wait or are stuck in Path C, point the deployment at a different `/24` subnet delegated to `Microsoft.App/environments`:

```bicep
param agentSubnetName = '<new-subnet-name>'
param agentSubnetPrefix = '<new-/24-range>'
```

---

## If `deleteCapHost.sh` Fails

| Failure | Likely cause | Fix |
|---------|--------------|-----|
| `Failed to get access token` | Not signed in | `az login`, then re-run |
| `404 Not Found` | Account is deleted, caphost name typo, or already deleted | If account is gone, use **Path B**. Otherwise re-run Step 1 to confirm the name. |
| Operation `Failed` referencing a project caphost | Project caphost still present | Delete project caphosts first (Path A, Step 2) |
| `403 Forbidden` | Missing RBAC | Grant Contributor or Cognitive Services Contributor on the account |

---

## Correct Cleanup Order (to avoid this next time)

1. Delete **project caphost**
2. Delete **project**
3. Delete **account caphost** (run `deleteCapHost.sh`)
4. Delete **account**
5. **Purge** the account (if you don't intend to recover it)

Skipping step 3 or 5 is what leaves the subnet locked.
