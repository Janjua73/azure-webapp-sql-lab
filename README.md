# Azure Secure Web Application Environment

A hands-on lab building a segmented, credential-free Azure environment: a Linux web app that reaches
an Azure SQL database over a private endpoint, with the database credential held in Key Vault and read
by the app's own managed identity. Built in the portal to learn the moving parts, then expressed as
Terraform.

Built on a personal Pay-As-You-Go subscription, deliberately kept to roughly 55p per day, then torn
down.

---

## Architecture

```
                    Internet
                       |
                       v
        +------------------------------+
        |   App Service (Linux, B1)    |
        |   app-lab-hammad-01          |
        |   system-assigned identity   |
        +------------------------------+
                 |                |
      VNet integration        Key Vault reference
      (snet-web)              (managed identity auth)
                 |                |
                 v                v
   +----------------------+  +----------------------+
   | Private endpoint     |  | Key Vault            |
   | pe-sql-lab           |  | kv-lab-hammad-01     |
   | snet-data  10.0.2.4  |  | RBAC, Secrets User   |
   +----------------------+  +----------------------+
                 |
                 v
     +-------------------------+
     | Azure SQL (serverless)  |
     | public access DISABLED  |
     +-------------------------+

   vnet-lab 10.0.0.0/16
     snet-web   10.0.1.0/24  (delegated to App Service)
     snet-data  10.0.2.0/24  (private subnet, no default outbound)
```

---

## Resources

| Resource | Name | Notes |
|---|---|---|
| Resource group | `rg-lab-uksouth` | UK South, one group so teardown is a single command |
| App Service plan | `ASP-rglabuksouth-909b` | B1 Linux — Basic is the minimum tier for VNet integration |
| Web app | `app-lab-hammad-01` | Python 3.12, basic authentication disabled |
| Virtual network | `vnet-lab` | 10.0.0.0/16 |
| Subnets | `snet-web`, `snet-data` | Web tier delegated to App Service; data tier private |
| Private endpoint | `pe-sql-lab` | Target sub-resource `sqlServer`, private IP 10.0.2.4 |
| Private DNS zone | `privatelink.database.windows.net` | Linked to `vnet-lab` |
| SQL server / database | `sql-lab-hammad-01` / `sqldb-lab` | General Purpose Serverless, free offer |
| Key Vault | `kv-lab-hammad-01` | Azure RBAC permission model |
| Monitoring | Application Insights, alert `alert-5xx` | Action group `ag-lab-email` |
| Budget | `lan-budget` | £5/month, alert-only |

---

## Network segmentation

The virtual network splits the tiers so they have different exposure. `snet-web` carries the App
Service integration; `snet-data` holds only the database's private endpoint and is a private subnet
with no default outbound access.

The web app was integrated into `snet-web` with **route-all outbound traffic** enabled. That setting
matters more than it appears: without it the app's outbound traffic bypasses the virtual network, so
it would neither resolve nor reach the private endpoint.

A private endpoint (`pe-sql-lab`) was then created for the SQL server in `snet-data`, with private DNS
integration. The zone `privatelink.database.windows.net` overrides the public hostname for anything
inside the VNet.

**Verification** — from the app's own SSH console:

```bash
python -c "import socket; print(socket.gethostbyname('sql-lab-hammad-01.database.windows.net'))"
10.0.2.4
```

The public hostname resolves to a private address inside `snet-data`, so the traffic never leaves the
virtual network.

With that proven, **public network access on the SQL server was disabled**. The existing firewall
rules are retained but inert — the point being that the private endpoint, not an IP allow-list, is
what now protects the database. The trade-off is real: the portal Query editor and any desktop SQL
client can no longer reach it, which is the correct behaviour for a database that should only be
reachable from its application tier.

### Why a private endpoint rather than a firewall rule

A server-level firewall rule still exposes a public endpoint and depends on an accurate, maintained
allow-list — which breaks the moment a home ISP rotates an address. A private endpoint removes the
public surface altogether, replacing "who is allowed to connect" with "what can route to it at all".

---

## Identity and secrets

The database credential is stored as the `SqlConnectionString` secret in Key Vault, which uses the
**Azure RBAC permission model** rather than legacy access policies.

A distinction worth recording, because it caused a genuine failure here: being **Owner** of the vault
does not grant the ability to read a secret. Owner is a control-plane role governing management of the
vault itself. Reading a secret value is a data-plane operation requiring a role such as Key Vault
Secrets Officer or Secrets User. Separating the two is the entire point of the RBAC model.

The app was given a **system-assigned managed identity**, whose lifecycle is tied to the app — delete
the app and the principal goes with it, leaving no orphaned credential. That identity was granted
**Key Vault Secrets User**, deliberately not Secrets Officer: an application that only fetches a
connection string should not be able to overwrite or delete it.

The app setting then holds a reference rather than a value:

```
SqlConnectionString = @Microsoft.KeyVault(SecretUri=https://kv-lab-hammad-01.vault.azure.net/secrets/SqlConnectionString/)
```

The trailing slash makes the reference versionless, so rotating the secret is picked up automatically
instead of leaving the app pointed at a dead version. The portal confirms resolution by showing the
setting's source as **Key vault** with a green tick — meaning the identity authenticated, was
authorised, and read the secret successfully.

Net result: no password, key or connection string is stored anywhere in the application's
configuration or source.

---

## Cost control

This ran on Pay-As-You-Go, which has **no hard spending limit**. Budgets raise alerts; they do not
stop spend, and they lag by hours. Cost control therefore had to come from resource choices:

- **Azure SQL serverless on the free offer** — 100,000 vCore-seconds and 32 GB storage per month, with
  **overage billing disabled** so the database pauses rather than bills. The only genuine hard stop in
  the environment.
- **Auto-pause** after one hour idle.
- **B1 App Service plan**, roughly 40p/day. App Service plans bill whether the app is running or
  stopped — stopping the app saves nothing, which is a common and expensive misunderstanding.
- **Private endpoint**, roughly 13p/day, created only when the networking work was actually being done
  rather than left running during study time.
- Microsoft Defender for SQL left off; it bills per server and adds nothing to a lab.

Total running cost was about 55p per day, and the environment was deleted once documented.

---

## Diagnosing a zero App Service quota

The first deployment failed with `Current Limit (B1 VMs): 0` — a new PAYG subscription had no App
Service quota at all, in UK South or North Europe.

Three things worth recording:

1. **Review + create validation does not check quota.** Validation passed every time; only pressing
   Create surfaced the real limit. Passing validation is not evidence that a deployment will succeed.
2. **The support request category determines whether anyone can help.** The first ticket, filed under
   "Other Requests", went nowhere for four days. The correct path is
   Quotas → *Function or Web App (Windows and Linux)*. The intake form requires a zone-redundant
   deployment type even when the actual deployment is not zone-redundant.
3. **AI assistance misdiagnosed it** as an ARM template preflight problem. The literal error text was
   correct and specific; the quota really was zero.

The second ticket was closed ten minutes after it was raised, with no explanation. The grant was only
discoverable by retrying the deployment.

---

## Deployment pipeline

Deployment is handled by GitHub Actions, configured through the App Service Deployment Center, with
the workflow committed to `.github/workflows/master_app-lab-hammad-01.yml`.

Authentication uses a **user-assigned managed identity federated with GitHub** rather than a stored
publish profile. Azure registers a federated credential trusting GitHub's token issuer for this
specific repository and branch; the workflow requests a short-lived token at deploy time and Azure
validates it against that trust. No secret is stored in GitHub, which matters here because basic
authentication is disabled on the app.

Two identity types are in play, doing different jobs:

| Identity | Type | Purpose |
|---|---|---|
| App's own identity | System-assigned | The app proving itself to Key Vault |
| Pipeline identity | User-assigned, federated | GitHub proving itself to Azure at deploy time |

### A deployment that succeeded while the app stayed down

The first successful pipeline run left the site serving Azure's default placeholder page. The
deployment genuinely had succeeded — the failure was downstream of it.

The previous method (`az webapp deployment source config --manual-integration`) pulled the repo and
ran Azure's Oryx build on the server, which installed the dependencies in `requirements.txt`. The
GitHub Actions workflow instead packages the repo and pushes it, and by default the platform does not
build on arrival. So `app.py` was present, Flask was not installed, gunicorn could not start the
application, and App Service fell back to the placeholder page.

Fixed by setting `SCM_DO_BUILD_DURING_DEPLOYMENT=true` so the platform builds the deployed package.

The lesson worth keeping: a green pipeline means the artifact arrived, not that the application runs.
Those are separate claims and need separate verification.

---

## Infrastructure as code

`/terraform` expresses the same environment as code: virtual network and subnets, the serverless
database with `use_free_limit` and overage disabled, Key Vault with RBAC, and outputs.

The portal build came first, deliberately — the aim was to understand each resource and its failure
modes before automating it. The Terraform is provided for review with `terraform init` and
`terraform plan`; it was not used to apply this environment.

Secrets are kept out of state: `terraform.tfvars`, `*.tfstate` and `.terraform/` are gitignored, since
local state stores values in clear text.

---

## Teardown

```bash
az group delete --name rg-lab-uksouth --yes
```

Keeping everything in one resource group is what makes cleanup a single command.

---

## Screenshots

| File | Shows |
|---|---|
| `docs/01-resource-group.png` | All resources in `rg-lab-uksouth` |
| `docs/02-subnets.png` | `snet-web` and `snet-data` |
| `docs/03-vnet-integration.png` | App Service integrated into `snet-web` |
| `docs/04-private-endpoint.png` | `pe-sql-lab` approved |
| `docs/05-public-access-disabled.png` | SQL public network access disabled |
| `docs/06-private-dns-resolution.png` | Hostname resolving to 10.0.2.4 from inside the app |
| `docs/07-managed-identity.png` | System-assigned identity enabled |
| `docs/08-role-assignment.png` | Key Vault Secrets User granted to the app |
| `docs/09-keyvault-reference.png` | App setting sourced from Key vault |
| `docs/10-app-live.png` | The running application |
| `docs/11-actions-run.png` | Successful GitHub Actions run (build and deploy) |
| `docs/12-deployment-center.png` | Deployment Center configured with federated identity |
| `docs/13-deployed-change.png` | A pushed change live on the site |
