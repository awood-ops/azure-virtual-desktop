# Getting Started

## Prerequisites

| Requirement | Notes |
|---|---|
| Azure subscription | Contributor on the target resource group |
| Azure DevOps organisation | For pipeline service connection |
| Azure CLI | 2.47+ with Bicep installed (`az bicep install`) |
| `Microsoft.DesktopVirtualization` resource provider | Register once per subscription |
| Virtual network with a subnet | Session hosts need an existing subnet to join |
| Domain / Entra ID join | Session hosts must be joinable (AD DS or Entra ID join) |

### Register resource provider

```bash
az provider register --namespace Microsoft.DesktopVirtualization --wait
az provider show -n Microsoft.DesktopVirtualization --query registrationState
```

## What this deploys

This repo deploys the **AVD control plane** only:

| Resource | Notes |
|---|---|
| Host pool | Manages the collection of session hosts |
| Desktop application group | Publishes the full desktop to users |
| Workspace | The end-user-facing entry point in the AVD client |
| Scaling plan (optional) | Auto-scales session hosts by schedule |

**Not deployed here:** session host VMs, virtual network, storage (FSLogix), DNS, Active Directory. These are prerequisites or managed separately.

## Session host enrolment

After deploying the host pool, generate a registration token:

```bash
az desktopvirtualization hostpool update \
  --name hp-avd-prd \
  --resource-group rg-avd-prd \
  --registration-info expiration-time=$(date -u -d '+2 hours' +%Y-%m-%dT%H:%MZ) registration-token-operation=Update
```

Then run `configuration/Script-SetupSessionHost.ps1` on each session host VM, passing the registration token. The script downloads `DeployAgent.zip` from Microsoft's endpoint and installs the RD agent.

## Azure DevOps service connection

Create a service connection named **`Azure-Service-Connection`** in your ADO project:

1. **Project Settings → Service connections → New → Azure Resource Manager → Service principal (automatic)**
2. Scope to subscription + resource group (`rg-avd-prd`)
3. Name: `Azure-Service-Connection`

## Assign users

After deployment, assign users or groups to the desktop application group:

```bash
az role assignment create \
  --assignee <user-or-group-object-id> \
  --role "Desktop Virtualization User" \
  --scope <appGroupId>
```

Users then connect via the [AVD web client](https://client.wvd.microsoft.com/arm/webclient/) or the Windows App / Remote Desktop client.
