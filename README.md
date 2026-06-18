# Identity Server

A centralized, enterprise-grade **Identity and Access Management (IAM)** solution built on [Duende IdentityServer](https://duendesoftware.com/products/identityserver). It implements **OAuth 2.0** and **OpenID Connect (OIDC)** protocols and ships with a Blazor-based admin portal for configuration management.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Features](#features)
- [Prerequisites](#prerequisites)
- [Getting Started](#getting-started)
- [Building the Solution](#building-the-solution)
- [Running the Applications](#running-the-applications)
- [Testing](#testing)
- [Database Setup](#database-setup)
- [Project Structure](#project-structure)
- [Configuration Reference](#configuration-reference)
- [Contributing](#contributing)
- [License](#license)

---

## Overview

Identity Server provides a secure token service for applications across the organisation. It supports multiple OAuth 2.0 flows, integrates with **Microsoft Entra ID** (formerly Azure AD) for user authentication, and stores all configuration and operational data in **SQL Server**. Secrets are managed via **Azure Key Vault** and **1Password**.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                          Clients / APIs                             │
└───────────────────────────┬─────────────────────────────────────────┘
                            │ OAuth 2.0 / OIDC
        ┌───────────────────▼──────────────────┐
        │         IdentityServer (Port 5200)    │
        │  • Authorization Code + PKCE          │
        │  • Client Credentials                 │
        │  • Token Exchange                     │
        │  • JWT & Reference Tokens             │
        └───────┬───────────────────┬───────────┘
                │                   │
   ┌────────────▼───┐     ┌─────────▼──────────────────┐
   │  SQL Server    │     │  Microsoft Entra ID         │
   │  (Duende EF   │     │  (OpenID Connect / Graph)   │
   │   Stores)     │     └─────────────────────────────┘
   └────────────────┘
                │
   ┌────────────▼──────────────────────────────────────┐
   │       Admin Portal (Port 5300)                    │
   │  ┌───────────────────┐  ┌────────────────────┐   │
   │  │  AdminPortal.     │  │  AdminPortal.Web   │   │
   │  │  Server (API)     │◄─│  (Blazor WASM UI)  │   │
   │  └───────────────────┘  └────────────────────┘   │
   └───────────────────────────────────────────────────┘

   Shared Infrastructure
   ┌──────────────┐  ┌───────────────────┐  ┌──────────────────┐
   │ Core / Data  │  │  MicrosoftGraph   │  │  OnePassword     │
   │ (EF, Cache,  │  │  (User/Group      │  │  (Secrets Vault) │
   │  Serilog)    │  │   Lookups)        │  │                  │
   └──────────────┘  └───────────────────┘  └──────────────────┘
```

---

## Features

### OAuth 2.0 / OpenID Connect
- Authorization Code flow with PKCE
- Client Credentials flow (machine-to-machine)
- Token Exchange (custom grant)
- JWT and reference token support
- Token introspection endpoint

### Authentication
- Microsoft Entra ID (OpenID Connect, v1.0 & v2.0)
- External login support
- JWT Bearer authentication for API consumers
- Configurable cookie lifetime

### Client & API Management
- Create and configure OAuth 2.0 clients
- Manage API resources, scopes, and claims
- Client secret rotation and CORS origin management
- Custom redirect URI validation
- Role-based access control (RBAC)

### Admin Portal
- Blazor WebAssembly UI for all configuration tasks
- User and group management (Entra ID linked)
- System permissions and role assignments
- Audit history and change tracking
- Import/export functionality

### Infrastructure
- Distributed caching with Redis / Valkey or in-memory
- Azure Key Vault for data-protection keys and the Duende licence key
- 1Password vault integration for runtime secret injection
- Serilog structured logging with a centralised log sink
- Health check endpoints
- Swagger / OpenAPI documentation (non-production environments)
- Windows Service hosting with WiX installer

---

## Prerequisites

| Requirement | Version |
|---|---|
| [.NET SDK](https://dotnet.microsoft.com/download) | 8.0 |
| [SQL Server](https://www.microsoft.com/en-gb/sql-server) | 2019+ |
| Azure subscription | Key Vault access required |
| 1Password account | Vault access for Entra credentials |
| Redis / Valkey *(optional)* | For distributed caching |

---

## Getting Started

### 1. Clone the repository

```bash
git clone https://github.com/sefe/identity-server.git
cd identity-server
```

### 2. Configure local settings

Each application reads configuration from the following sources (highest priority last):

1. `appsettings.json` – base settings
2. `appsettings.local.json` – local overrides (committed as examples; must not contain secrets)
3. Environment variables
4. .NET User Secrets (development)
5. 1Password Vault – Entra ID credentials injected at startup
6. Azure Key Vault – data-protection keys and Duende licence

Update `appsettings.local.json` in both locations (these files are already committed as examples):
- `src/IdentityServer/IdentityServer/`
- `src/IdentityServer.UI.Admin/IdentityServer.AdminPortal.Server/`

Minimum required settings:

```json
{
  "ConnectionStrings": {
    "IDPDBConnectionString": "Server=localhost;Database=IdentityServer;Trusted_Connection=True;"
  }
}
```

> **SQL Authentication:** If Windows Authentication is not available (e.g. in containers or cross-platform environments), use SQL credentials instead:
> ```
> Server=localhost;Database=IdentityServer;User Id=<user>;Password=<password>;
> ```
> Store credentials in [.NET User Secrets](https://learn.microsoft.com/en-us/aspnet/core/security/app-secrets) or environment variables — never commit them to `appsettings.json`.

```json
{
  "MicrosoftEntra": {
    "ClientId": "<your-entra-app-client-id>",
    "TenantId": "<your-entra-tenant-id>",
    "ClientSecret": "<your-entra-client-secret>"
  },
  "AzureKeyVault": {
    "Uri": "https://<your-keyvault>.vault.azure.net/"
  }
}
```

### 3. Set up the database

See [Database Setup](#database-setup) below.

---

## Building the Solution

```bash
# Identity Server
dotnet build src/IdentityServer/IdentityServer.sln

# Admin Portal
dotnet build src/IdentityServer.UI.Admin/IdentityServer.AdminPortal.sln
```

---

## Running the Applications

```bash
# Identity Server – https://localhost:5200
dotnet run --project src/IdentityServer/IdentityServer/IdentityServer.csproj

# Admin Portal – https://localhost:5300
dotnet run --project src/IdentityServer.UI.Admin/IdentityServer.AdminPortal.Server/IdentityServer.AdminPortal.Server.csproj
```

Swagger UI is available at `https://localhost:5200/swagger` in non-production environments.

---

## Testing

The solution contains 12 test projects using **NUnit**, **NSubstitute**, and **AutoFixture**.

```bash
# Run all Identity Server tests
dotnet test src/IdentityServer/IdentityServer.sln

# Run all Admin Portal tests
dotnet test src/IdentityServer.UI.Admin/IdentityServer.AdminPortal.sln

# Run a specific test project
dotnet test src/IdentityServer.Common/IdentityServer.Data.Test/IdentityServer.Data.Test.csproj
```

---

## Database Setup

The database schema is managed as a **SQL Server DACPAC** project (`src/IdentityServer.Database/`).

### Deploy the DACPAC

Publish using Visual Studio SQL Server Data Tools or the `sqlpackage` CLI:

```bash
sqlpackage /Action:Publish \
  /SourceFile:"IdentityServer.Database.dacpac" \
  /TargetConnectionString:"<connection-string>"
```

### Post-deployment scripts

Post-deployment scripts run in the following order:

| Folder | Purpose |
|---|---|
| `Post/BeforeEnvironmentSpecific/` | Runs first; environment-agnostic seed data |
| `Post/EnvironmentSpecific/{env}/` | Environment-specific data (`DV`, `QA`, `PP`, `PROD`) |
| `Post/AfterEnvironmentSpecific/` | Runs last; finalisation steps |

> **Note:** After adding a new script, right-click `PostDeploymentAggregation.tt` and select **Run Custom Tool** to regenerate the aggregation script. Without this step the new script will not be included in the DACPAC.

---

## Project Structure

```
identity-server/
├── src/
│   ├── IdentityServer/                    # OAuth 2.0 / OIDC server solution
│   │   ├── IdentityServer/                # Main API – token generation & validation
│   │   ├── IdentityServer.Setup/          # WiX installer project
│   │   └── IdentityServer.Test/           # Integration & unit tests
│   │
│   ├── IdentityServer.Common/             # Shared libraries solution
│   │   ├── IdentityServer.Abstraction/    # Interfaces, contracts, constants, enums
│   │   ├── IdentityServer.Core/           # Caching, config, DI, HTTP resilience
│   │   ├── IdentityServer.Core.Serilog/   # Serilog configuration & custom sinks
│   │   ├── IdentityServer.Data/           # EF Core DbContext, repositories, migrations
│   │   ├── IdentityServer.MicrosoftGraph/ # Microsoft Graph / Entra ID integration
│   │   ├── IdentityServer.OnePassword/    # 1Password secrets management
│   │   └── *Tests/                        # Unit tests for each library
│   │
│   ├── IdentityServer.Database/           # SQL Server DACPAC project
│   │   ├── dbo/                           # Tables, views, stored procedures
│   │   ├── Security/                      # Roles and permissions
│   │   └── Post/                          # Post-deployment scripts
│   │
│   └── IdentityServer.UI.Admin/           # Admin portal solution
│       ├── IdentityServer.AdminPortal.Server/  # ASP.NET Core backend API
│       ├── IdentityServer.AdminPortal.Web/     # Blazor WASM frontend
│       ├── IdentityServer.AdminPortal.Setup/   # WiX installer project
│       └── IdentityServer.AdminPortal.Test/    # Tests
│
├── CONTRIBUTING.md
├── LICENSE.md
└── README.md
```

---

## Configuration Reference

### System

| Key | Description | Example |
|---|---|---|
| `System:SystemName` | Application name for logging | `IdentityServer` |
| `System:EnvironmentTier` | Deployment tier | `DV`, `QA`, `PP`, `PROD` |
| `System:LoadBalancer:IpRange` | Load balancer IP for forwarded-header trust | `10.0.0.0` |

### Caching

| Key | Description |
|---|---|
| `IdentityServer:CachingOptions:Enabled` | Enable/disable distributed caching |
| `IdentityServer:CachingOptions:Provider:Kind` | Cache provider: `InMemory` or `Valkey` |
| `IdentityServer:CachingOptions:Provider:ConnectionString` | Valkey connection string (Valkey only) |
| `IdentityServer:CachingOptions:Provider:Username` | Valkey username (Valkey only) |
| `IdentityServer:CachingOptions:Provider:Password` | Valkey password (Valkey only) |

### Feature Flags

| Key | Description |
|---|---|
| `FeatureFlags:UseCustomRedirectUriValidator` | Enable loopback redirect URI validation (development) |
| `FeatureFlags:CustomTokenLoggingSettings:EnableCustomTokenLogging` | Enable detailed token event logging |

---

## Contributing

Contributions are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) for the full guidelines.

In short:

1. Fork the repository and create your branch from `main`.
2. Add tests for any new functionality.
3. Update documentation if APIs change.
4. Ensure `dotnet test` passes.
5. Open a pull request.

---

## License

This project is licensed under the **Apache License 2.0**. See [LICENSE.md](LICENSE.md) for details.