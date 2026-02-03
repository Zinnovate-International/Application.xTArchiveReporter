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

## IIS Deployment (Manual)
1. Download the workflow artifact zip.
2. Unzip to a folder (e.g., `C:\inetpub\xTArchiveReporter`).
3. In IIS Manager:
   - Add a new site named `xTArchiveReporter` pointing to the extracted folder.
   - Set the application pool to `.NET CLR v4.0` (No Managed Code) and enable 64-bit.
4. Ensure the connection string points to your production SQL instance.

## Troubleshooting
- `Cannot open database "xTArchive" requested by the login` → Ensure the DB exists and `sa` has access.
- Docker SQL Server failing on ARM → use Azure SQL Edge or run the AMD64 image with `--platform linux/amd64`.
- Frontend `Unexpected token '<'` → ensure Vite proxy forwards `/api/*` to ASP.NET (already configured in `vite.config.js`).
