# Azure Web App + SQL Lab

A small but production-shaped Azure environment built by hand in the portal: a segmented virtual
network, a serverless SQL database, secrets in Key Vault, and (pending quota) an App Service with
private networking and a CI/CD pipeline.

Built as self-directed study alongside AZ-104 preparation. Region: **UK South**.

> **Status: in progress.** The App Service half is blocked on an Azure subscription quota limit
> (see [Quota constraint](#quota-constraint)). Everything else is built and working.

---

## Architecture

```
                         Internet
                            │
                            ▼
              ┌──────────────────────────┐
              │  App Service (B1, Linux) │   ← pending quota
              │  app-lab-hammad-01       │
              │  Python 3.12             │
              └────────────┬─────────────┘
                           │ VNet integration
   vnet-lab  10.0.0.0/16   │
   ┌───────────────────────┼────────────────────────┐
   │                       ▼                        │
   │   snet-web  10.0.1.0/24                        │
   │                                                │
   │   snet-data 10.0.2.0/24                        │
   │        │                                       │
   │        ▼  private endpoint (deferred - hourly) │
   └────────┼───────────────────────────────────────┘
            ▼
   ┌────────────────────────────┐     ┌─────────────────────────┐
   │ Azure SQL (serverless)     │     │ Key Vault (RBAC)        │
   │ sql-lab-hammad-01          │     │ kv-lab-hammad-01        │
   │ sqldb-lab                  │◄────┤ SqlConnectionString     │
   └────────────────────────────┘     └─────────────────────────┘
```

---

## What is built

| Resource | Name | Notes |
|---|---|---|
| Resource group | `rg-lab-uksouth` | Everything lives here, so teardown is one action |
| Virtual network | `vnet-lab` | 10.0.0.0/16 |
| Subnet (web tier) | `snet-web` | 10.0.1.0/24, default outbound access enabled |
| Subnet (data tier) | `snet-data` | 10.0.2.0/24, private subnet - no default outbound |
| SQL logical server | `sql-lab-hammad-01` | SQL + Microsoft Entra authentication |
| SQL database | `sqldb-lab` | General Purpose serverless, free offer, auto-pause |
| Key Vault | `kv-lab-hammad-01` | Azure RBAC permission model |
| Budget | `lab-budget` | £5/month with alerts at 50/80/100% actual and 100% forecast |

### Network segmentation

A `/16` address space split into two `/24` subnets, divided by exposure rather than by convenience.
The web tier accepts traffic from the internet; the data tier must not. Separating them means
network rules can be applied at the subnet boundary, and it gives the SQL private endpoint somewhere
to live where nothing else can reach it.

`snet-data` is configured as a **private subnet** (no default outbound internet access), because the
only thing that will ever sit in it is a private endpoint, which needs no egress. `snet-web` keeps
default outbound access, because removing it would require a NAT gateway for the App Service to
reach the internet.

Each `/24` provides 251 usable addresses, not 256 — Azure reserves the first four and the last one
in every subnet.

### Database

`sqldb-lab` runs on the **General Purpose serverless** tier under Azure SQL's free offer:
100,000 vCore-seconds, 32 GB data and 32 GB backup storage per month.

Two settings do the cost control:

- **Auto-pause after 1 hour idle.** Serverless bills per vCore-second of actual activity, so a
  paused database costs nothing for compute. The trade-off is a cold start of a few seconds on the
  first query after a pause — acceptable for a lab, not acceptable for a customer-facing app. That
  trade-off is the reason serverless is not a universal default.
- **Overage billing disabled.** When the free monthly allowance is exhausted the database pauses
  until the next month rather than falling through to paid rates. This is the only genuine hard
  cost stop available on a pay-as-you-go subscription.

Schema:

```sql
CREATE TABLE dbo.Messages (
    MessageId   INT IDENTITY(1,1) PRIMARY KEY,
    Body        NVARCHAR(200) NOT NULL,
    CreatedUtc  DATETIME2(0)  NOT NULL
        CONSTRAINT DF_Messages_CreatedUtc DEFAULT SYSUTCDATETIME()
);
```

Encryption is on by default in both directions: Transparent Data Encryption at rest with a
service-managed key, and TLS in transit (`Encrypt=True` in the connection string).

### Secrets

Key Vault uses the **Azure RBAC** permission model rather than the legacy vault access policies.

An important distinction this makes concrete: being subscription **Owner** is a control-plane role.
It permits deleting the vault but not reading what is inside it. Data-plane access is a separate
role assignment — `Key Vault Secrets Officer` to read and write, `Key Vault Secrets User` to read
only. The App Service's managed identity will be granted **Secrets User**, because an application
that only needs to fetch a connection string has no business being able to overwrite it.

The SQL connection string is stored as the secret `SqlConnectionString` rather than in application
configuration.

**Intended end state:** Azure SQL also offers Entra passwordless authentication
(`Authentication="Active Directory Default"`), where the App Service's managed identity is a SQL
user and the connection string contains no credential at all. That is strictly better than storing
a password well — there is nothing to leak and nothing to rotate. The Key Vault path is implemented
here first because the mechanics are worth knowing.

---

## Cost control

Pay-as-you-go subscriptions have **no hard spending limit**. The Azure spending limit feature exists
only on credit-based subscriptions, and Cost Management budgets are alerts, not caps — and they lag
several hours behind actual usage, so they catch a slow leak rather than a spike.

Real cost control here comes from three things:

1. Free-tier and serverless SKUs wherever possible, with overage billing disabled on the database.
2. Understanding what bills continuously. An App Service Plan charges whether the app inside it is
   running or stopped — stopping the app does not stop the bill, only deleting the plan does.
3. A single resource group, so teardown is one action.

The private endpoint is **deliberately deferred**. It bills hourly (roughly £6/month) whether or not
anything is using it, so it will be created at the end, demonstrated, screenshotted, and removed
with the rest of the environment rather than left running while other work is blocked.

Spend at time of writing: **£0.00**.

---

## Quota constraint

App Service deployment is currently blocked by a subscription-level quota limit. Every attempt to
create an App Service Plan fails with:

```
Operation cannot be completed without additional quota.
Current Limit (B1 VMs): 0
Current Usage: 0
Amount required for this deployment (B1 VMs): 1
```

Diagnosis: the limit is **0 for every SKU tested** — F1, B1 and P0V3 — and in more than one region.
New pay-as-you-go subscriptions ship this way as an anti-abuse measure. It is not a billing problem,
and no change of tier or region resolves it.

Two things worth recording:

- The portal's **Review + create** validation does not check quota. A clean validation screen proves
  nothing; the error only appears after pressing Create. This caused two false positives before it
  was understood.
- Azure Copilot misdiagnosed the failure as an ARM template preflight error and recommended
  `az deployment group validate`. The actual error text names the SKU, the region's limit and the
  current usage explicitly. Reading the literal error beat following the suggested cause.

Resolution in progress via Microsoft support (quota increase request, correctly categorised under
*Service and Subscription Limits (Quotas) → Function or Web App (Windows and Linux)* after an initial
mis-filing).

---

## Still to build

- App Service (B1, Linux, Python) with Application Insights and an alert rule on HTTP 5xx
- Regional VNet integration into `snet-web`
- Private endpoint for SQL in `snet-data`, then disable the database's public endpoint
- Managed identity on the App Service, granted `Key Vault Secrets User`, reading the connection
  string via a Key Vault reference so no credential sits in app configuration
- A second identity with `Reader` on the resource group, to demonstrate least-privilege role
  assignment
- GitHub Actions deployment pipeline, ideally using OIDC federated credentials rather than a stored
  publish profile

---

## Teardown

```
az group delete --name rg-lab-uksouth --yes
```

One command removes every resource above.
