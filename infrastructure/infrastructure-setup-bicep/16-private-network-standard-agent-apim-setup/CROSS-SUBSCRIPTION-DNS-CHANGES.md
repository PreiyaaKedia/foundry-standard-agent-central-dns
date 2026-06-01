# Cross-Subscription Private DNS Zone Support

## Background

Customers running a hub-and-spoke topology commonly keep their `privatelink.*` zones in a **central DNS subscription** (the hub), separate from the subscription where workloads (private endpoints) are deployed.

The previous version of this template only accepted a **resource group name** for each existing DNS zone and always resolved the zone in the **deployment subscription**. When customers passed a central-DNS RG name, the compiled ARM template produced zone IDs like:

```
/subscriptions/<DEPLOYMENT-SUB>/resourceGroups/<central-dns-rg>/providers/Microsoft.Network/privateDnsZones/...
```

Those zones do not exist in the deployment subscription, so Azure rejected the private endpoint DNS Zone Group creation with:

```
InvalidPrivateDnsZoneIds — Private Dns Zone group ... has invalid private dns zone ids
```

Azure itself **does** support cross-subscription private DNS zones for private endpoints — this was purely a template limitation.

## What changed

The `existingDnsZones` parameter schema changed from `string` (resource group only) to an **object** per zone:

```jsonc
{
  "<zone-fqdn>": {
    "subscriptionId":    "<guid or empty>",   // empty => deployment subscription
    "resourceGroupName": "<rg  or empty>"     // empty => create zone locally
  }
}
```

Behavior matrix:

| `resourceGroupName` | `subscriptionId` | Outcome                                                                                       |
|---------------------|------------------|-----------------------------------------------------------------------------------------------|
| empty               | (ignored)        | Template **creates** a new private DNS zone in the deployment RG and links it to the VNet.     |
| set                 | empty            | Template **references existing zone** in the deployment subscription (previous behavior).      |
| set                 | set              | Template **references existing zone in a different subscription** (new: central / hub DNS).    |

When an existing zone is referenced (either same- or cross-sub), the template **skips creating the VNet link**; the link must already exist in the hub.

## Files modified

| File | Change |
|------|--------|
| `modules-network-secured/private-endpoint-and-dns.bicep` | `existingDnsZones` param shape updated; new per-zone `*DnsZoneSub` vars; all 7 `existing` zone references now scope with `resourceGroup(sub, rg)`. |
| `modules-network-secured/validate-existing-resources.bicep` | DNS zone existence check reads `.resourceGroupName`. |
| `main.bicep` | Default value of `existingDnsZones` updated to new object shape; description expanded. |
| `main.bicepparam` | Example values updated; comment block explains the new shape. |
| `azuredeploy.parameters.json` | Default values updated. |
| `main.json`, `azuredeploy.json` | Recompiled from updated Bicep. |

## Usage example — central DNS subscription

```jsonc
"existingDnsZones": {
  "value": {
    "privatelink.services.ai.azure.com":       { "subscriptionId": "<hub-dns-sub-guid>", "resourceGroupName": "rg-hub-dns" },
    "privatelink.openai.azure.com":            { "subscriptionId": "<hub-dns-sub-guid>", "resourceGroupName": "rg-hub-dns" },
    "privatelink.cognitiveservices.azure.com": { "subscriptionId": "<hub-dns-sub-guid>", "resourceGroupName": "rg-hub-dns" },
    "privatelink.search.windows.net":          { "subscriptionId": "<hub-dns-sub-guid>", "resourceGroupName": "rg-hub-dns" },
    "privatelink.blob.core.windows.net":       { "subscriptionId": "<hub-dns-sub-guid>", "resourceGroupName": "rg-hub-dns" },
    "privatelink.documents.azure.com":         { "subscriptionId": "<hub-dns-sub-guid>", "resourceGroupName": "rg-hub-dns" },
    "privatelink.azure-api.net":               { "subscriptionId": "",                   "resourceGroupName": ""           }
  }
}
```

## Usage example — let the template create everything

```jsonc
"existingDnsZones": {
  "value": {
    "privatelink.services.ai.azure.com":       { "subscriptionId": "", "resourceGroupName": "" },
    "privatelink.openai.azure.com":            { "subscriptionId": "", "resourceGroupName": "" },
    "privatelink.cognitiveservices.azure.com": { "subscriptionId": "", "resourceGroupName": "" },
    "privatelink.search.windows.net":          { "subscriptionId": "", "resourceGroupName": "" },
    "privatelink.blob.core.windows.net":       { "subscriptionId": "", "resourceGroupName": "" },
    "privatelink.documents.azure.com":         { "subscriptionId": "", "resourceGroupName": "" },
    "privatelink.azure-api.net":               { "subscriptionId": "", "resourceGroupName": "" }
  }
}
```

## Prerequisites when using a central DNS subscription

These are owned by the customer/hub-networking team and are **not** created by this template:

1. **VNet link** — each referenced zone must already be linked to the workload VNet (`Microsoft.Network/privateDnsZones/virtualNetworkLinks`). Without the link, name resolution silently fails after a successful deployment.
2. **RBAC** — the principal running this deployment needs `Private DNS Zone Contributor` on the central DNS zones' resource group so the private endpoint can write its A-record into the zone.
3. (Optional) If your environment uses an Azure Policy `DeployIfNotExists` to auto-register PE A-records in the hub, you can leave `existingDnsZones` empty — but you should then **delete the locally created zones** post-deployment to avoid split-brain resolution.

## Breaking change note

This is a **breaking parameter-shape change**. Existing parameter files using the string form must be migrated to the object form. There is no shim; the template fails with a property-access error if the old shape is used.
