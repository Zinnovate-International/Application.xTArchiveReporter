#Requires -Version 7.0
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Installs xTArchiveReporter on Windows Server 2025 with IIS.

.DESCRIPTION
    This script automates the full server-side installation of xTArchiveReporter:
      - Enables IIS and all required Windows features
      - Downloads and installs the ASP.NET Core Hosting Bundle (.NET 9)
      - Optionally downloads and installs Web Deploy 4.0
      - Deploys the application to a configurable local path
      - Creates an IIS Application Pool (No Managed Code) and Website
      - Writes the SQL Server connection string into appsettings.json
      - Sets NTFS permissions for the IIS AppPool identity
      - Opens Windows Firewall ports 80 and 443
      - Optionally binds a self-signed TLS certificate
      - Performs a post-install HTTP smoke-test

.PARAMETER PackagePath
    Full path to the xTArchiveReporter Web Deploy zip produced by the CI pipeline
    (Application.xTArchiveReporter.Server.zip).  Supply either this parameter or
    -PackageUrl.  If neither is given the script searches the current directory for
    a matching .zip file.

.PARAMETER PackageUrl
    URL from which the script will download the deployment zip before installing.

.PARAMETER InstallPath
    Target folder on the server where the application files are placed.
    Defaults to C:\inetpub\xTArchiveReporter.

.PARAMETER SiteName
    IIS website name.  Defaults to "xTArchiveReporter".

.PARAMETER AppPoolName
    IIS application pool name.  Defaults to "xTArchiveReporter".

.PARAMETER HttpPort
    HTTP port for the IIS binding.  Defaults to 80.

.PARAMETER HttpsPort
    HTTPS port for the IIS binding.  Defaults to 443.
    Pass 0 to skip the HTTPS binding.

.PARAMETER SqlServer
    SQL Server host and optional port, e.g. "localhost" or "sql.example.com,1433".
    Defaults to "localhost,1433".

.PARAMETER SqlDatabase
    Database name.  Defaults to "xTArchive".

.PARAMETER SqlUser
    SQL login username.  Defaults to "sa".

.PARAMETER SqlPassword
    SQL login password.  You will be prompted if this is omitted.

.PARAMETER CertValidityYears
    Number of years the self-signed TLS certificate will be valid.
    Defaults to 2.  Ignored when -SkipSelfSignedCert is specified.

.PARAMETER SkipWebDeploy
    When specified, the Web Deploy 4.0 installer is not downloaded or run.

.PARAMETER SkipSelfSignedCert
    When specified, no self-signed certificate is created and the HTTPS binding
    is added without a certificate (useful when a real certificate will be bound
    separately afterwards).

.EXAMPLE
    # Minimal – use a local zip, prompt for the SA password
    .\Install-xTArchiveReporter.ps1 -PackagePath ".\Application.xTArchiveReporter.Server.zip"

.EXAMPLE
    # Download the zip from a URL with all options specified
    .\Install-xTArchiveReporter.ps1 `
        -PackageUrl "https://example.com/release/Application.xTArchiveReporter.Server.zip" `
        -InstallPath "D:\Apps\xTArchiveReporter" `
        -SqlServer "sqlserver.corp.local,1433" `
        -SqlDatabase "xTArchive" `
        -SqlUser "appuser" `
        -SqlPassword "S3cur3P@ss!" `
        -HttpPort 8080 `
        -HttpsPort 0

.NOTES
    Tested on: Windows Server 2025 (Desktop Experience), PowerShell 7.4+
    Run this script from an elevated PowerShell 7 session.
    Internet access is required to download the Hosting Bundle and Web Deploy
    unless the relevant parameters are skipped and the software is pre-installed.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]  $PackagePath,
    [string]  $PackageUrl,
    [string]  $InstallPath       = 'C:\inetpub\xTArchiveReporter',
    [string]  $SiteName          = 'xTArchiveReporter',
    [string]  $AppPoolName       = 'xTArchiveReporter',
    [int]     $HttpPort          = 80,
    [int]     $HttpsPort         = 443,
    [string]  $SqlServer         = 'localhost,1433',
    [string]  $SqlDatabase       = 'xTArchive',
    [string]  $SqlUser           = 'sa',
    [string]  $SqlPassword,
    [int]     $CertValidityYears  = 2,
    [switch]  $SkipWebDeploy,
    [switch]  $SkipSelfSignedCert
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ─── Helpers ──────────────────────────────────────────────────────────────────

function Write-Step  { param([string]$msg) Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Ok    { param([string]$msg) Write-Host "    [OK] $msg" -ForegroundColor Green }
function Write-Warn  { param([string]$msg) Write-Host "    [WARN] $msg" -ForegroundColor Yellow }
function Write-Fail  { param([string]$msg) Write-Host "    [FAIL] $msg" -ForegroundColor Red; throw $msg }

function Invoke-Download {
    param([string]$Url, [string]$Destination)
    Write-Host "    Downloading: $Url"
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing
    Write-Ok "Saved to $Destination"
}

function Test-WindowsFeature {
    param([string]$Name)
    $feature = Get-WindowsFeature -Name $Name -ErrorAction SilentlyContinue
    return ($null -ne $feature -and $feature.Installed)
}

function Wait-IIS {
    $maxWait = 30
    $elapsed = 0
    while ($elapsed -lt $maxWait) {
        try {
            $svc = Get-Service -Name 'W3SVC' -ErrorAction SilentlyContinue
            if ($null -ne $svc -and $svc.Status -eq 'Running') { return }
        } catch { }
        Start-Sleep -Seconds 2
        $elapsed += 2
    }
    Write-Warn 'W3SVC did not reach Running state within 30 s – continuing anyway.'
}

# ─── 1. OS / prerequisite check ───────────────────────────────────────────────

Write-Step 'Checking prerequisites'

$os = Get-CimInstance Win32_OperatingSystem
Write-Host "    OS : $($os.Caption) build $($os.BuildNumber)"

if ($os.ProductType -eq 1) {
    Write-Warn 'This is a workstation OS. The script is designed for Windows Server.'
}

# Ensure Server Manager module is available (required for Get-WindowsFeature)
if (-not (Get-Command Get-WindowsFeature -ErrorAction SilentlyContinue)) {
    Write-Fail 'Get-WindowsFeature is not available. Run this script on Windows Server.'
}

Write-Ok 'Prerequisites satisfied.'

# ─── 2. Collect SQL password ──────────────────────────────────────────────────

if (-not $SqlPassword) {
    $secPwd = Read-Host -Prompt "    Enter SQL password for '$SqlUser'" -AsSecureString
    $bstr   = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secPwd)
    $SqlPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
}

# ─── 3. IIS and required Windows Features ────────────────────────────────────

Write-Step 'Installing IIS and required Windows Features'

$features = @(
    'Web-Server',             # IIS base
    'Web-WebServer',
    'Web-Common-Http',
    'Web-Default-Doc',
    'Web-Dir-Browsing',
    'Web-Http-Errors',
    'Web-Static-Content',
    'Web-Http-Redirect',
    'Web-Health',
    'Web-Http-Logging',
    'Web-Log-Libraries',
    'Web-Request-Monitor',
    'Web-Http-Tracing',
    'Web-Performance',
    'Web-Stat-Compression',
    'Web-Dyn-Compression',
    'Web-Security',
    'Web-Filtering',
    'Web-Basic-Auth',
    'Web-Windows-Auth',
    'Web-App-Dev',
    'Web-Net-Ext45',
    'Web-Asp-Net45',
    'Web-ISAPI-Ext',
    'Web-ISAPI-Filter',
    'Web-Mgmt-Tools',
    'Web-Mgmt-Console',
    'Web-Mgmt-Compat',
    'Web-Metabase'
)

$toInstall = $features | Where-Object { -not (Test-WindowsFeature -Name $_) }

if ($toInstall) {
    Write-Host "    Installing: $($toInstall -join ', ')"
    Install-WindowsFeature -Name $toInstall -IncludeManagementTools | Out-Null
    Write-Ok 'IIS features installed.'
} else {
    Write-Ok 'All required IIS features already present.'
}

# Ensure the WebAdministration module is loaded
Import-Module WebAdministration -ErrorAction Stop

# ─── 4. ASP.NET Core Hosting Bundle (.NET 9) ─────────────────────────────────

Write-Step 'Installing ASP.NET Core Hosting Bundle for .NET 9'

# Detect whether the .NET 9 Hosting Bundle (ANCM v2) is already present
$ancmKey = 'HKLM:\SOFTWARE\Microsoft\IIS Extensions\IIS ASP.NET Core Module V2'
$dotnet9Present = $false
if (Test-Path $ancmKey) {
    $ancmProps = Get-ItemProperty $ancmKey -ErrorAction SilentlyContinue
    if ($null -ne $ancmProps -and $null -ne $ancmProps.Version) {
        $dotnet9Present = $ancmProps.Version -like '9.*'
    }
}

if ($dotnet9Present) {
    Write-Ok 'ASP.NET Core Hosting Bundle for .NET 9 already installed.'
} else {
    $tmpBundle = Join-Path $env:TEMP 'dotnet-hosting-9-bundle.exe'
    # The permanent redirect URL always resolves to the latest .NET 9 Hosting Bundle
    $bundleUrl = 'https://aka.ms/dotnet/9.0/dotnet-hosting-win.exe'
    Invoke-Download -Url $bundleUrl -Destination $tmpBundle

    Write-Host '    Running Hosting Bundle installer (silent)…'
    $proc = Start-Process -FilePath $tmpBundle `
        -ArgumentList '/install', '/quiet', '/norestart', 'OPT_NO_SHAREDFX=0' `
        -Wait -PassThru
    if ($proc.ExitCode -ne 0 -and $proc.ExitCode -ne 3010) {
        Write-Fail "Hosting Bundle installer exited with code $($proc.ExitCode)."
    }
    Write-Ok '.NET 9 Hosting Bundle installed.'
    Remove-Item $tmpBundle -Force -ErrorAction SilentlyContinue
}

# ─── 5. Web Deploy 4.0 (optional) ────────────────────────────────────────────

if (-not $SkipWebDeploy) {
    Write-Step 'Installing Web Deploy 4.0'

    $wdReg  = 'HKLM:\SOFTWARE\Microsoft\IIS Extensions\MSDeploy\3'
    $wdPresent = $false
    if (Test-Path $wdReg) {
        $wdProps = Get-ItemProperty $wdReg -ErrorAction SilentlyContinue
        if ($null -ne $wdProps -and $null -ne $wdProps.Version) {
            try {
                $wdPresent = ([version]$wdProps.Version -ge [version]'3.6')
            } catch {
                Write-Warn "Could not parse Web Deploy version '$($wdProps.Version)' – will reinstall."
            }
        }
    }

    if ($wdPresent) {
        Write-Ok 'Web Deploy already installed.'
    } else {
        $tmpWd  = Join-Path $env:TEMP 'WebDeploy_amd64_en-US.msi'
        $wdUrl  = 'https://download.microsoft.com/download/0/1/D/01DC28EA-638C-4A22-A57B-4CEF97755C6C/WebDeploy_amd64_en-US.msi'
        Invoke-Download -Url $wdUrl -Destination $tmpWd

        Write-Host '    Running Web Deploy installer (silent)…'
        $proc = Start-Process -FilePath 'msiexec.exe' `
            -ArgumentList "/i `"$tmpWd`" ADDLOCAL=ALL /quiet /norestart" `
            -Wait -PassThru
        if ($proc.ExitCode -ne 0 -and $proc.ExitCode -ne 3010) {
            Write-Fail "Web Deploy installer exited with code $($proc.ExitCode)."
        }
        Write-Ok 'Web Deploy 4.0 installed.'
        Remove-Item $tmpWd -Force -ErrorAction SilentlyContinue
    }
} else {
    Write-Step 'Skipping Web Deploy installation (–SkipWebDeploy specified)'
}

# ─── 6. Locate / download the deployment package ─────────────────────────────

Write-Step 'Locating deployment package'

if (-not $PackagePath -and $PackageUrl) {
    $PackagePath = Join-Path $env:TEMP 'xTArchiveReporter_deploy.zip'
    Invoke-Download -Url $PackageUrl -Destination $PackagePath
}

if (-not $PackagePath) {
    # Auto-discover in the current directory
    $found = Get-ChildItem -Path (Get-Location) -Filter 'Application.xTArchiveReporter.Server.zip' -ErrorAction SilentlyContinue |
             Select-Object -First 1
    if ($found) {
        $PackagePath = $found.FullName
        Write-Ok "Auto-discovered package: $PackagePath"
    } else {
        Write-Fail 'No deployment package found. Provide -PackagePath or -PackageUrl.'
    }
}

if (-not (Test-Path $PackagePath)) {
    Write-Fail "Package not found at: $PackagePath"
}

Write-Ok "Using package: $PackagePath"

# ─── 7. Deploy application files ─────────────────────────────────────────────

Write-Step "Deploying application to $InstallPath"

# Stop the IIS site if it already exists (avoids file-lock errors)
if (Test-Path "IIS:\Sites\$SiteName" -ErrorAction SilentlyContinue) {
    Write-Host "    Stopping existing IIS site '$SiteName'…"
    Stop-WebSite -Name $SiteName -ErrorAction SilentlyContinue
}

if (-not (Test-Path $InstallPath)) {
    New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
}

# The Web Deploy zip produced by IISProfile.pubxml is a Web Deploy package, but
# for a direct file deployment we expand it and pull out the Content folder.
# If the zip has a top-level Content\C_C\... structure (Web Deploy layout) we
# handle that; otherwise we treat the zip as a plain publish output.
$tmpExtract = Join-Path $env:TEMP 'xTArchiveReporter_extract'
if (Test-Path $tmpExtract) { Remove-Item $tmpExtract -Recurse -Force }
Expand-Archive -Path $PackagePath -DestinationPath $tmpExtract -Force

# Determine the content root inside the zip
$contentRoot = $tmpExtract

# Web Deploy packages wrap files under Content\C_C\inetpub\<site>\...
# Try to detect that layout.
$wdContent = Get-ChildItem -Path $tmpExtract -Recurse -Directory |
             Where-Object { $_.Name -eq 'Content' } |
             Select-Object -First 1

if ($null -ne $wdContent) {
    # Drill down: Content\<drive_root>\...
    $innerDirs = Get-ChildItem -Path $wdContent.FullName -Directory
    if ($innerDirs.Count -eq 1) {
        $innerDirs2 = Get-ChildItem -Path $innerDirs[0].FullName -Directory
        if ($innerDirs2.Count -ge 1) {
            $contentRoot = $innerDirs2[0].FullName
            Write-Host "    Web Deploy layout detected – content root: $contentRoot"
        }
    }
}

# Copy files to the install path (overwrite existing)
Write-Host "    Copying files…"
Copy-Item -Path (Join-Path $contentRoot '*') -Destination $InstallPath -Recurse -Force
Write-Ok "Application files deployed to $InstallPath."

# Cleanup temp extraction
Remove-Item $tmpExtract -Recurse -Force -ErrorAction SilentlyContinue

# ─── 8. Configure connection string ──────────────────────────────────────────

Write-Step 'Configuring appsettings.json'

$appSettings = Join-Path $InstallPath 'appsettings.json'
if (-not (Test-Path $appSettings)) {
    Write-Warn "appsettings.json not found at $appSettings – skipping connection string update."
} else {
    $json = Get-Content $appSettings -Raw | ConvertFrom-Json

    $connStr = "Server=$SqlServer;Database=$SqlDatabase;User Id=$SqlUser;Password=$SqlPassword;TrustServerCertificate=True"

    if ($null -eq $json.ConnectionStrings) {
        $json | Add-Member -NotePropertyName 'ConnectionStrings' -NotePropertyValue ([PSCustomObject]@{}) -Force
    }
    $json.ConnectionStrings | Add-Member -NotePropertyName 'MetainfDb' -NotePropertyValue $connStr -Force

    $json | ConvertTo-Json -Depth 10 | Set-Content $appSettings -Encoding UTF8
    Write-Ok "Connection string written to $appSettings."
    Write-Warn 'The SQL password is stored in plain text in appsettings.json.'
    Write-Warn "Restrict NTFS access to that file, or use Windows Authentication / Azure Key Vault in production."
}

# ─── 9. IIS Application Pool ─────────────────────────────────────────────────

Write-Step "Creating IIS Application Pool '$AppPoolName'"

if (Test-Path "IIS:\AppPools\$AppPoolName") {
    Write-Ok "Application pool '$AppPoolName' already exists – reusing."
} else {
    New-WebAppPool -Name $AppPoolName | Out-Null
    Write-Ok "Application pool '$AppPoolName' created."
}

# ASP.NET Core runs as self-hosted; pool must be No Managed Code
Set-ItemProperty "IIS:\AppPools\$AppPoolName" -Name managedRuntimeVersion -Value ''
Set-ItemProperty "IIS:\AppPools\$AppPoolName" -Name startMode -Value 'AlwaysRunning'
Set-ItemProperty "IIS:\AppPools\$AppPoolName" -Name processModel.idleTimeout -Value ([TimeSpan]::Zero)
Set-ItemProperty "IIS:\AppPools\$AppPoolName" -Name recycling.periodicRestart.time -Value ([TimeSpan]::Zero)

Write-Ok "Application pool configured."

# ─── 10. IIS Website ──────────────────────────────────────────────────────────

Write-Step "Creating IIS Website '$SiteName'"

$bindingInfo = "*:${HttpPort}:"

if (Test-Path "IIS:\Sites\$SiteName") {
    Write-Ok "Website '$SiteName' already exists – updating physical path."
    Set-ItemProperty "IIS:\Sites\$SiteName" -Name physicalPath -Value $InstallPath
    Set-ItemProperty "IIS:\Sites\$SiteName" -Name applicationPool -Value $AppPoolName
} else {
    New-Website -Name $SiteName `
                -PhysicalPath $InstallPath `
                -ApplicationPool $AppPoolName `
                -Port $HttpPort `
                -Force | Out-Null
    Write-Ok "Website '$SiteName' created on port $HttpPort."
}

# ─── 11. HTTPS binding (optional) ────────────────────────────────────────────

if ($HttpsPort -gt 0) {
    Write-Step "Configuring HTTPS binding on port $HttpsPort"

    $certThumb = $null

    if (-not $SkipSelfSignedCert) {
        # Create a self-signed certificate valid for the configured number of years
        $hostname = [System.Net.Dns]::GetHostName()
        $cert = New-SelfSignedCertificate `
            -DnsName $hostname, 'localhost' `
            -CertStoreLocation 'Cert:\LocalMachine\My' `
            -NotAfter (Get-Date).AddYears($CertValidityYears) `
            -FriendlyName "xTArchiveReporter – $hostname"
        $certThumb = $cert.Thumbprint
        Write-Ok "Self-signed certificate created (thumbprint: $certThumb, valid $CertValidityYears year(s))."
    }

    # Add the HTTPS binding
    $httpsBinding = Get-WebBinding -Name $SiteName -Protocol 'https' -Port $HttpsPort -ErrorAction SilentlyContinue
    if ($null -eq $httpsBinding) {
        New-WebBinding -Name $SiteName -Protocol 'https' -Port $HttpsPort -IPAddress '*' -SslFlags 0 | Out-Null
        Write-Ok "HTTPS binding added on port $HttpsPort."
    } else {
        Write-Ok "HTTPS binding on port $HttpsPort already present."
    }

    if ($certThumb) {
        # Bind the certificate to the port via netsh.
        # Use a deterministic GUID derived from the site name so re-runs are idempotent.
        $guidBytes = [System.Text.Encoding]::UTF8.GetBytes($SiteName.ToLowerInvariant())
        $guidHash  = [System.Security.Cryptography.MD5]::Create().ComputeHash($guidBytes)
        $appId = '{' + [System.Guid]::new($guidHash).ToString() + '}'

        # Remove any existing binding on this port (ignore 'not found' errors)
        $deleteOut = netsh http delete sslcert ipport="0.0.0.0:$HttpsPort" 2>&1
        if ($deleteOut -notmatch 'successfully deleted|cannot find') {
            Write-Warn "netsh delete sslcert: $deleteOut"
        }

        $addOut = netsh http add sslcert ipport="0.0.0.0:$HttpsPort" certhash=$certThumb appid=$appId certstorename=MY 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "netsh add sslcert returned exit code $LASTEXITCODE : $addOut"
        } else {
            Write-Ok "Certificate bound to port $HttpsPort (appid: $appId)."
        }
    }
} else {
    Write-Step 'Skipping HTTPS binding (–HttpsPort 0 specified)'
}

# ─── 12. NTFS permissions ─────────────────────────────────────────────────────

Write-Step 'Setting NTFS permissions'

$identity = "IIS AppPool\$AppPoolName"
$acl = Get-Acl $InstallPath
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    $identity,
    'ReadAndExecute, Write, ListDirectory',
    'ContainerInherit, ObjectInherit',
    'None',
    'Allow'
)
$acl.AddAccessRule($rule)
Set-Acl -Path $InstallPath -AclObject $acl
Write-Ok "Granted ReadAndExecute+Write to '$identity' on $InstallPath."

# ─── 13. Firewall rules ───────────────────────────────────────────────────────

Write-Step 'Configuring Windows Firewall'

$fwRules = @(
    @{ Name = 'xTArchiveReporter HTTP';  Port = $HttpPort;  Protocol = 'TCP' }
)
if ($HttpsPort -gt 0) {
    $fwRules += @{ Name = 'xTArchiveReporter HTTPS'; Port = $HttpsPort; Protocol = 'TCP' }
}

foreach ($rule in $fwRules) {
    $existing = Get-NetFirewallRule -DisplayName $rule.Name -ErrorAction SilentlyContinue
    if ($null -ne $existing) {
        Write-Ok "Firewall rule '$($rule.Name)' already present."
    } else {
        New-NetFirewallRule `
            -DisplayName $rule.Name `
            -Direction Inbound `
            -Protocol $rule.Protocol `
            -LocalPort $rule.Port `
            -Action Allow `
            -Profile Any | Out-Null
        Write-Ok "Firewall rule '$($rule.Name)' created for port $($rule.Port)."
    }
}

# ─── 14. Start IIS ───────────────────────────────────────────────────────────

Write-Step 'Starting IIS and the application site'

# Restart W3SVC to pick up the new Hosting Bundle ANCM module if it was just installed
Restart-Service -Name W3SVC -Force -ErrorAction SilentlyContinue
Wait-IIS

Start-WebAppPool -Name $AppPoolName -ErrorAction SilentlyContinue
Start-WebSite -Name $SiteName -ErrorAction SilentlyContinue

Write-Ok 'IIS started.'

# ─── 15. Smoke test ───────────────────────────────────────────────────────────

Write-Step 'Running smoke test'

Start-Sleep -Seconds 5  # allow ANCM to initialise

$smokeUrl = "http://localhost:$HttpPort/"
try {
    $response = Invoke-WebRequest -Uri $smokeUrl -UseBasicParsing -TimeoutSec 15
    if ($response.StatusCode -lt 400) {
        Write-Ok "Smoke test passed – HTTP $($response.StatusCode) from $smokeUrl"
    } else {
        Write-Warn "Smoke test returned HTTP $($response.StatusCode) from $smokeUrl – check the application logs."
    }
} catch {
    Write-Warn "Smoke test request to $smokeUrl failed: $_"
    Write-Warn 'This may be normal if SQL Server is not yet reachable. Check IIS logs and application logs.'
}

# ─── Done ─────────────────────────────────────────────────────────────────────

Write-Host ''
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host " xTArchiveReporter installation complete!" -ForegroundColor Cyan
Write-Host "   Site name    : $SiteName" -ForegroundColor Cyan
Write-Host "   App pool     : $AppPoolName" -ForegroundColor Cyan
Write-Host "   Install path : $InstallPath" -ForegroundColor Cyan
Write-Host "   HTTP URL     : http://localhost:$HttpPort/" -ForegroundColor Cyan
if ($HttpsPort -gt 0) {
    Write-Host "   HTTPS URL    : https://localhost:$HttpsPort/" -ForegroundColor Cyan
}
Write-Host ''
Write-Host ' Next steps:' -ForegroundColor Yellow
Write-Host '  1. Verify SQL Server is reachable from this server.' -ForegroundColor Yellow
Write-Host "  2. Check the connection string in: $appSettings" -ForegroundColor Yellow
Write-Host '  3. Browse to the HTTP URL above to confirm the UI loads.' -ForegroundColor Yellow
if (-not $SkipSelfSignedCert -and $HttpsPort -gt 0) {
    Write-Host '  4. Replace the self-signed certificate with a trusted one for production.' -ForegroundColor Yellow
}
Write-Host '============================================================' -ForegroundColor Cyan
