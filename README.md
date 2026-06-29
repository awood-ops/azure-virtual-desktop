# Azure Virtual Desktop

End-to-end Bicep deployment for [Azure Virtual Desktop](https://learn.microsoft.com/en-us/azure/virtual-desktop/overview) — networking, FSLogix storage, Key Vault, AVD control plane, and session hosts. All layers are optional flags to support both greenfield and brownfield deployments.

## Architecture

```mermaid
graph TB
    User(["👤 User\n(AVD Client)"])

    subgraph Azure["Azure Subscription — rg-avd-prd"]
        subgraph Net["Networking"]
            VNet["VNet\n10.20.0.0/16"]
            HostSubnet["snet-avd-hosts"]
            PESubnet["snet-avd-pe"]
            NSG["NSG"]
        end

        subgraph Sec["Security"]
            KV["🔑 Key Vault\nvm-admin-password"]
        end

        subgraph Store["Storage"]
            SA["Azure Files\nFSLogix profiles\n(Premium + Entra Kerberos)"]
        end

        subgraph Control["AVD Control Plane"]
            WS["Workspace"]
            AG["App Group\n(Desktop)"]
            HP["Host Pool"]
            SP["Scaling Plan"]
        end

        subgraph Hosts["Session Hosts"]
            VM0["avd-prd-0\nWin11 Multi-session"]
            VM1["avd-prd-1\nWin11 Multi-session"]
        end
    end

    User -->|connects via| WS
    WS --> AG --> HP
    HP --> VM0 & VM1
    SP -.-|auto-scale| HP
    KV -.-|"kv.getSecret()"| VM0 & VM1
    SA -.-|UNC profile path| VM0 & VM1
    VM0 & VM1 --- HostSubnet --- VNet
    SA --- PESubnet --- VNet
    NSG --- HostSubnet
```

## Deployment flow

```mermaid
flowchart LR
    Start([az deployment\ngroup create]) --> KV & Net & AVD

    KV{deployKeyVault} -->|true| KV1[Create Key Vault]
    KV1 --> KV2[Generate &amp; store\nvm-admin-password]

    Net{deployNetworking} -->|true| Net1[VNet + Subnets\n+ NSG]

    AVD[AVD Control Plane] --> HP[Host Pool]
    AVD --> AG[App Group]
    AVD --> WS[Workspace]

    Net1 & KV2 --> SH

    Store{deployStorage} -->|true| Store1[Azure Files\nfor FSLogix]
    Store1 --> SH

    HP -->|reg token| SH{deploySessionHosts}
    SH -->|true| VM[Deploy VMs]
    VM --> Join[Entra ID Join]
    Join --> Agent[AVD Agent\n+ FSLogix config]
```

## Structure

```
.azuredevops/
├── Deploy-AVD.yaml              # CD pipeline — deploys on push to main
└── PR-Validation.yaml           # CI pipeline — validates Bicep on PRs

.github/workflows/
└── check-avm-versions.yml       # Weekly AVM version check — auto-raises PRs

bicep/
├── main.bicep                   # Orchestrator — wires all modules together
├── main.bicepparam              # Parameters (customise per environment)
└── modules/
    ├── networking.bicep         # VNet, session host subnet, PE subnet, NSG
    ├── keyvault.bicep           # Key Vault + auto-generated VM admin password
    ├── storage.bicep            # Azure Files (Premium, Entra Kerberos) for FSLogix
    ├── avd-control-plane.bicep  # Host pool, app group, workspace, scaling plan
    └── session-hosts.bicep      # Win11 multi-session VMs, Entra ID join, AVD agent

docs/
└── Getting-Started.md           # Prerequisites, enrolment, user assignment

scripts/
└── Update-AvmVersions.py        # AVM version checker (used by GitHub Actions)

bicepconfig.json                 # AVM public registry alias
```

## AVM modules used

| Module | Version | Resource |
|---|---|---|
| `avm/res/network/network-security-group` | 0.4.0 | NSG |
| `avm/res/network/virtual-network` | 0.4.0 | VNet and subnets |
| `avm/res/key-vault/vault` | 0.9.0 | Key Vault |
| `avm/res/storage/storage-account` | 0.14.0 | FSLogix Azure Files |
| `avm/res/desktop-virtualization/host-pool` | 0.3.0 | Host pool |
| `avm/res/desktop-virtualization/application-group` | 0.2.0 | Desktop app group |
| `avm/res/desktop-virtualization/workspace` | 0.3.0 | Workspace |
| `avm/res/desktop-virtualization/scaling-plan` | 0.2.0 | Auto-scaling (optional) |
| `avm/res/compute/virtual-machine` | 0.11.0 | Session host VMs |

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

No credentials are needed at deploy time — the VM admin password is auto-generated and stored in Key Vault on first deploy.

## Credentials and Key Vault

The deployment script in `modules/keyvault.bicep` generates a strong random password on first deploy and stores it as `vm-admin-password` in Key Vault. On re-deploy the existing secret is left unchanged. `main.bicep` passes the secret to session hosts via `kv.getSecret()` — the value is never exposed in parameters, pipeline variables, or deployment outputs.

**Retrieve the password (break-glass):**
```bash
az keyvault secret show --vault-name avd-prd-kv --name vm-admin-password --query value -o tsv
```

**Rotate the password:**
```bash
az keyvault secret delete --vault-name avd-prd-kv --name vm-admin-password
# then re-deploy
```

## Contributing

Changes go through a pull request. The PR validation pipeline runs `az bicep build` and a preflight `validate` before merge. AVM module versions are checked weekly and updated automatically via pull request.
