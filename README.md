# Azure Virtual Desktop

Bicep templates and Azure DevOps pipelines to deploy and manage an [Azure Virtual Desktop](https://learn.microsoft.com/en-us/azure/virtual-desktop/overview) environment — host pool, workspace, application group, and optional scaling plan.

## Structure

```
.azuredevops/
├── Deploy-AVD.yaml            # CD pipeline — deploys on push to main
└── PR-Validation.yaml         # CI pipeline — validates Bicep on PRs

.github/workflows/
└── check-avm-versions.yml     # Weekly AVM version check — auto-raises PRs

bicep/
├── main.bicep                 # Entry point — calls AVM modules
└── main.bicepparam            # Parameters (customise per environment)

configuration/                 # Session host setup scripts
├── Script-SetupSessionHost.ps1
├── Script-TestSetupSessionHost.ps1
├── Configuration.ps1
├── AvdFunctions.ps1
└── Functions.ps1

docs/
└── Getting-Started.md

scripts/
└── Get-SessionHostStatus.ps1

bicepconfig.json               # AVM public registry alias
```

## AVM modules used

| Module | Version | Resource |
|---|---|---|
| `avm/res/desktop-virtualization/host-pool` | 0.3.0 | Host pool |
| `avm/res/desktop-virtualization/application-group` | 0.2.0 | Desktop app group |
| `avm/res/desktop-virtualization/workspace` | 0.3.0 | Workspace |
| `avm/res/desktop-virtualization/scaling-plan` | 0.2.0 | Auto-scaling (optional) |

Check latest versions: [AVM Bicep Resource Modules](https://azure.github.io/Azure-Verified-Modules/indexes/bicep/bicep-resource-modules/)

## Quick start

See [docs/Getting-Started.md](docs/Getting-Started.md) for prerequisites and network requirements.

```bash
az bicep restore --file bicep/main.bicep

az deployment group validate \
  --resource-group rg-avd-prd \
  --template-file bicep/main.bicep \
  --parameters bicep/main.bicepparam

az deployment group create \
  --resource-group rg-avd-prd \
  --template-file bicep/main.bicep \
  --parameters bicep/main.bicepparam
```

## Session host configuration

After deploying the host pool, session hosts are enrolled using the scripts in `configuration/`. The AVD agent installer (`DeployAgent.zip`) is downloaded by `Script-SetupSessionHost.ps1` from Microsoft's endpoint at enrolment time — it is not stored in this repo.

## Contributing

Changes go through a pull request. The PR validation pipeline runs `az bicep build` and a preflight `validate` before merge. AVM module versions are checked weekly and updated automatically via pull request.
