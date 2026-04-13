# xTArchiveReporter

xTArchiveReporter is a .NET 9 + React 19 application that exposes Metainf aggregation data through an ASP.NET Core backend and a Vite-powered frontend. The solution lets users filter Metainf incidents by object paths and date ranges, view aggregated counts, and export results to Excel.

## Solution Structure

| Path | Description |
| --- | --- |
| `Application.xTArchiveReporter.Server/` | ASP.NET Core Web API (controllers, EF Core DbContext, models). |
| `application.xtarchivereporter.client/` | React 19 SPA built with Vite. |
| `.github/workflows/build-and-package.yml` | GitHub Action that builds both apps and publishes a zip artifact for IIS deployment. |

## Requirements

- .NET SDK 9.0+
- Node.js 20+
- SQL Server 2022 / SQL Server Express / Azure SQL Edge (container instructions below)
- PowerShell 7+ (recommended) or your preferred shell
- IIS Hosting Bundle + Web Deploy 4.0 (only for IIS servers)

## Local Development

1. **Restore & build backend**
   ```powershell
   dotnet restore Application.xTArchiveReporter.Server/Application.xTArchiveReporter.Server.csproj
   dotnet build Application.xTArchiveReporter.Server/Application.xTArchiveReporter.Server.csproj
   ```
2. **Install frontend deps & run dev server**
   ```powershell
   cd application.xtarchivereporter.client
   npm install
   npm run dev
   ```
   The Vite dev server proxies `/api/*` calls to ASP.NET (configure `ASPNETCORE_URLS` as needed).
3. **Run backend**
   ```powershell
   dotnet run --project Application.xTArchiveReporter.Server/Application.xTArchiveReporter.Server.csproj
   ```
4. Open the Vite URL (default `https://localhost:60629`) and use the filter form.

### Local Publishing (IIS-ready)

Before running `dotnet publish`, prepare the frontend bundle:

```powershell
cd application.xtarchivereporter.client
npm run build
cd ..
dotnet publish Application.xTArchiveReporter.Server/Application.xTArchiveReporter.Server.csproj -c Release -p:PublishProfile=IISProfile
```

This uses the `IISProfile.pubxml` Web Deploy package profile, which automatically runs the SPA build script and drops `Publish\Application.xTArchiveReporter.Server.zip` ready for IIS import.

## Database Setup

### Docker SQL Server 2022
```powershell
docker run --platform linux/amd64 `
  -e "ACCEPT_EULA=Y" `
  -e "SA_PASSWORD=<Strong!Passw0rd>" `
  -p 1433:1433 `
  -v C:\data\sqlscripts:/data `
  --name sqlmetainf `
  -d mcr.microsoft.com/mssql/server:2022-latest
```
Create the database:
```powershell
sqlcmd -S localhost,1433 -U sa -P "<Strong!Passw0rd>" -Q "IF DB_ID('xTArchive') IS NULL CREATE DATABASE [xTArchive];"
```
Import seed data:
```powershell
sqlcmd -S localhost,1433 -U sa -P "<Strong!Passw0rd>" -d xTArchive -i C:\data\sqlscripts\metainf-seed.sql
```

### Azure SQL Edge (ARM hosts)
```powershell
docker run --platform linux/arm64/v8 `
  -e "ACCEPT_EULA=Y" `
  -e "SA_PASSWORD=<Strong!Passw0rd>" `
  -p 1433:1433 `
  -v C:\data\sqlscripts:/data `
  --name sqlmetainf-edge `
  -d mcr.microsoft.com/azure-sql-edge
```
Import using host `sqlcmd` (Edge image lacks tools by default):
```powershell
sqlcmd -S localhost,1433 -U sa -P "<Strong!Passw0rd>" -d xTArchive -i C:\data\sqlscripts\metainf-seed.sql
```

Update `Application.xTArchiveReporter.Server/appsettings.json` with:
```json
"ConnectionStrings": {
  "MetainfDb": "Server=localhost,1433;Database=xTArchive;User Id=sa;Password=<Strong!Passw0rd>;TrustServerCertificate=True"
}
```

## Excel Export Endpoint
`GET /api/metainfaggregations/export` returns an `.xlsx` file containing:
- Export metadata (UTC timestamp, applied filters)
- Aggregated rows grouped by From / Contract / To paths

The React UI calls this endpoint via the “Export to Excel” button.

## GitHub Action
The workflow `build-and-package.yml` runs on pushes/PRs to `main`:
1. Builds frontend (Node 20 + Vite).
2. Publishes the backend (`dotnet publish -c Release`).
3. Zips the publish folder into `xTArchiveReporter_IIS.zip`.
4. Uploads the zip as the `xTArchiveReporter_IIS_Package` artifact (ready for IIS deployment).

## IIS Deployment on Windows Server 2025 (Automated)

The repository ships `Install-xTArchiveReporter.ps1` – a self-contained PowerShell 7 script that fully automates the IIS deployment on Windows Server 2025 (and Windows Server 2022).

### What the script does

| Step | Action |
| --- | --- |
| 1 | Verifies the OS and that the session is elevated |
| 2 | Enables IIS + all required Windows features |
| 3 | Downloads and installs the **ASP.NET Core Hosting Bundle for .NET 9** |
| 4 | Optionally downloads and installs **Web Deploy 4.0** |
| 5 | Extracts the deployment package to `C:\inetpub\xTArchiveReporter` (configurable) |
| 6 | Writes the SQL Server connection string into `appsettings.json` |
| 7 | Creates an IIS Application Pool (**No Managed Code**, Always Running) |
| 8 | Creates an IIS Website with HTTP (and optional HTTPS) bindings |
| 9 | Optionally generates a self-signed TLS certificate and binds it |
| 10 | Grants the AppPool identity the required NTFS permissions |
| 11 | Opens Windows Firewall rules for the configured ports |
| 12 | Restarts IIS and runs a smoke-test HTTP request |

### Prerequisites

- Windows Server 2025 (Desktop Experience or Core)
- **PowerShell 7.0+** (`winget install Microsoft.PowerShell`)
- An elevated (Run as Administrator) PowerShell session
- The `Application.xTArchiveReporter.Server.zip` artifact from the CI pipeline (or a download URL)
- Network access to download the Hosting Bundle and Web Deploy (or pre-install them and use `-SkipWebDeploy`)

### Quick start

```powershell
# 1. Download the CI artifact, then run from an elevated PowerShell 7 session:
.\Install-xTArchiveReporter.ps1 -PackagePath ".\Application.xTArchiveReporter.Server.zip"

# The script will prompt for the SQL password if -SqlPassword is omitted.
```

### Full example with all parameters

```powershell
.\Install-xTArchiveReporter.ps1 `
    -PackageUrl  "https://example.com/release/Application.xTArchiveReporter.Server.zip" `
    -InstallPath "D:\Apps\xTArchiveReporter" `
    -SiteName    "xTArchiveReporter" `
    -AppPoolName "xTArchiveReporter" `
    -HttpPort    80 `
    -HttpsPort   443 `
    -SqlServer   "sqlserver.corp.local,1433" `
    -SqlDatabase "xTArchive" `
    -SqlUser     "appuser" `
    -SqlPassword "S3cur3P@ss!" `
    -SkipWebDeploy        # omit if you want Web Deploy installed
```

### Parameters

| Parameter | Default | Description |
| --- | --- | --- |
| `-PackagePath` | *(auto-discover)* | Local path to the deployment zip |
| `-PackageUrl` | – | URL to download the zip from |
| `-InstallPath` | `C:\inetpub\xTArchiveReporter` | Deployment target folder |
| `-SiteName` | `xTArchiveReporter` | IIS website name |
| `-AppPoolName` | `xTArchiveReporter` | IIS application pool name |
| `-HttpPort` | `80` | HTTP port |
| `-HttpsPort` | `443` | HTTPS port (pass `0` to skip) |
| `-SqlServer` | `localhost,1433` | SQL Server host[:port] |
| `-SqlDatabase` | `xTArchive` | Database name |
| `-SqlUser` | `sa` | SQL login username |
| `-SqlPassword` | *(prompted)* | SQL login password |
| `-CertValidityYears` | `2` | Validity period (years) for the self-signed certificate |
| `-SkipWebDeploy` | – | Skip Web Deploy 4.0 installation |
| `-SkipSelfSignedCert` | – | Skip self-signed cert creation |

## IIS Deployment (Manual)

### Server prerequisites

1. Install the latest **ASP.NET Core Hosting Bundle** on the IIS machine (includes the .NET runtime + ASP.NET Core Module).
2. Install **Web Deploy 4.0** so IIS Manager can import Web Deploy packages.

### Deploy
1. Download the workflow artifact zip.
2. Import the Web Deploy package (`Application.xTArchiveReporter.Server.zip`) in IIS Manager (Deploy > Import Application...)
3. Point the deployment to `C:\inetpub\xTArchiveReporter` (or desired folder) and let the wizard create/update the site.
4. Ensure the application pool runs as **No Managed Code** and that the connection string targets your production SQL instance.

## Troubleshooting
- `Cannot open database "xTArchive" requested by the login` → Ensure the DB exists and `sa` has access.
- Docker SQL Server failing on ARM → use Azure SQL Edge or run the AMD64 image with `--platform linux/amd64`.
- Frontend `Unexpected token '<'` → ensure Vite proxy forwards `/api/*` to ASP.NET (already configured in `vite.config.js`).
