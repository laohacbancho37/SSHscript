# =========================================================================
# SCRIPT CAI DAT CLOUDFLARE TUNNEL SSH (DANG PURE POWERSHELL)
# =========================================================================

# Kiem tra quyen Administrator
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    if ($MyInvocation.MyCommand.Path) {
        Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Path)`"" -Verb RunAs
    }
    else {
        Write-Host "[!] Vui long mo PowerShell voi quyen Administrator (Run as Administrator) va chay lai!" -ForegroundColor Red
        Start-Sleep -Seconds 5
    }
    exit
}

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# Bắt lỗi toàn cục
trap {
    Write-Host "`n[LOI CAI DAT]: $($_.Exception.Message)" -ForegroundColor Red
    Start-Sleep -Seconds 5
    exit 1
}
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# =========================================================================
# CAU HINH CA NHAN
# =========================================================================

$CloudflareAPIToken = "WOlfQgZG8gYZ50VmrpuscoK0ym6P9kELgYxp8gMe"
$CloudflareAccountId = "66ca9d4c586baabe040066154621c353"
$CloudflareZoneId = "b808f8b8eb32b2a826ad9b2600afc6ad"
$BaseDomain = "laohacbancho37.id.vn"

# Noi dung khoa Public Key
$SshPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMk83rs0xpy8XOhogglSmppmkYenUEfMGdsGsGsebB29 laohacbancho37@A"

# =========================================================================

$SshdFound = $false

if (Get-Service -Name sshd -ErrorAction SilentlyContinue) {
    $SshdFound = $true
}
else {
    try {
        if (Get-Command Add-WindowsCapability -ErrorAction SilentlyContinue) {
            Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 -ErrorAction SilentlyContinue | Out-Null
        }
    } catch {}

    if (Get-Service -Name sshd -ErrorAction SilentlyContinue) {
        $SshdFound = $true
    }
    elseif (Test-Path "$env:ProgramFiles\OpenSSH-Win64\install-sshd.ps1") {
        $OpenSshDir = "$env:ProgramFiles\OpenSSH-Win64"
        Push-Location $OpenSshDir
        try {
            & powershell.exe -ExecutionPolicy Bypass -File "$OpenSshDir\install-sshd.ps1" | Out-Null
        } finally {
            Pop-Location
        }
        if (Get-Service -Name sshd -ErrorAction SilentlyContinue) {
            $SshdFound = $true
        }
    }
}

if (-not $SshdFound) {
    $ZipPath = "$env:TEMP\OpenSSH-Win64.zip"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri "https://github.com/PowerShell/Win32-OpenSSH/releases/download/v9.5.0.0p1-Beta/OpenSSH-Win64.zip" -OutFile $ZipPath -UseBasicParsing
    
    Expand-Archive -Path $ZipPath -DestinationPath $env:ProgramFiles -Force
    $OpenSshDir = "$env:ProgramFiles\OpenSSH-Win64"
    
    Push-Location $OpenSshDir
    try {
        & powershell.exe -ExecutionPolicy Bypass -File "$OpenSshDir\install-sshd.ps1" | Out-Null
    } finally {
        Pop-Location
    }
    
    $retry = 0
    while (-not (Get-Service -Name sshd -ErrorAction SilentlyContinue) -and $retry -lt 10) {
        Start-Sleep -Seconds 1
        $retry++
    }

    $HostKeyDir = "$env:ProgramData\ssh"
    if (Test-Path $HostKeyDir) {
        $keys = Get-ChildItem -Path $HostKeyDir -Filter "*_key"
        foreach ($key in $keys) {
            icacls.exe $key.FullName /inheritance:r /grant "SYSTEM:(F)" "Administrators:(F)" /c /q | Out-Null
        }
    }
    
    $currentPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    if ($currentPath -notmatch "OpenSSH") {
        [Environment]::SetEnvironmentVariable("Path", "$currentPath;$OpenSshDir", "Machine")
    }
    Remove-Item $ZipPath -Force -ErrorAction SilentlyContinue
    
    if (!(Test-Path "HKLM:\SOFTWARE\OpenSSH")) { New-Item -Path "HKLM:\SOFTWARE\OpenSSH" -Force -ErrorAction SilentlyContinue | Out-Null }
    New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell -Value "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
}

if (Get-Service -Name sshd -ErrorAction SilentlyContinue) {
    Start-Service sshd -ErrorAction SilentlyContinue
    Set-Service -Name sshd -StartupType 'Automatic' -ErrorAction SilentlyContinue
}

if (!(Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue | Select-Object Name, Enabled)) {
    New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
}

$Headers = @{
    "Authorization" = "Bearer $CloudflareAPIToken"
    "Content-Type"  = "application/json"
}

try {
    $TunnelsRes = Invoke-RestMethod -Uri "https://api.cloudflare.com/client/v4/accounts/$CloudflareAccountId/cfd_tunnel?is_deleted=false&per_page=100" -Method Get -Headers $Headers
    $ExistingTunnels = @($TunnelsRes.result.name)
}
catch {
    $ExistingTunnels = @()
}

$whoamiUser = (whoami).Split('\')[-1].Trim() -replace '[^a-zA-Z0-9-]', ''
if ([string]::IsNullOrWhiteSpace($whoamiUser)) {
    $whoamiUser = $env:USERNAME -replace '[^a-zA-Z0-9-]', ''
}
if ([string]::IsNullOrWhiteSpace($whoamiUser)) {
    $whoamiUser = "sshuser"
}

$InputName = $whoamiUser
$TunnelName = $InputName
$i = 1
while ($ExistingTunnels -contains $TunnelName) {
    $TunnelName = "$InputName$i"
    $i++
}

# Tao Secret 
$bytes = New-Object byte[] 32
$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$rng.GetBytes($bytes)
$TunnelSecret = [Convert]::ToBase64String($bytes)

# [2.1] Tao Tunnel

$TunnelBody = @{
    name          = $TunnelName
    tunnel_secret = $TunnelSecret
    config_src    = "cloudflare"
} | ConvertTo-Json

try {
    $TunnelRes = Invoke-RestMethod -Uri "https://api.cloudflare.com/client/v4/accounts/$CloudflareAccountId/cfd_tunnel" -Method Post -Headers $Headers -Body $TunnelBody
    $TunnelId = $TunnelRes.result.id
}
catch {
    Write-Host "[LOI] Khong the tao Tunnel: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Lay Token Tunnel

try {
    $TokenRes = Invoke-RestMethod -Uri "https://api.cloudflare.com/client/v4/accounts/$CloudflareAccountId/cfd_tunnel/$TunnelId/token" -Method Get -Headers $Headers
    $TunnelToken = $TokenRes.result
}
catch {
    Write-Host "[LOI] Khong the lay Tunnel Token: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# [2.3.1] Cau hinh Tunnel Route 

$ConfigBody = @{
    config = @{
        ingress = @(
            @{
                hostname = "$TunnelName.$BaseDomain"
                service  = "ssh://localhost:22"
            },
            @{
                service = "http_status:404"
            }
        )
    }
} | ConvertTo-Json -Depth 10

try {
    Invoke-RestMethod -Uri "https://api.cloudflare.com/client/v4/accounts/$CloudflareAccountId/cfd_tunnel/$TunnelId/configurations" -Method Put -Headers $Headers -Body $ConfigBody | Out-Null
}
catch {}

# [2.3.2] Tao hoac Cap nhat CNAME DNS 

$DnsBody = @{
    type    = "CNAME"
    name    = $TunnelName
    content = "$TunnelId.cfargotunnel.com"
    proxied = $true
} | ConvertTo-Json

try {
    $ExistingDns = Invoke-RestMethod -Uri "https://api.cloudflare.com/client/v4/zones/$CloudflareZoneId/dns_records?name=$TunnelName.$BaseDomain" -Method Get -Headers $Headers
    if ($ExistingDns.result -and $ExistingDns.result.Count -gt 0) {
        $RecordId = $ExistingDns.result[0].id
        Invoke-RestMethod -Uri "https://api.cloudflare.com/client/v4/zones/$CloudflareZoneId/dns_records/$RecordId" -Method Put -Headers $Headers -Body $DnsBody | Out-Null
    } else {
        Invoke-RestMethod -Uri "https://api.cloudflare.com/client/v4/zones/$CloudflareZoneId/dns_records" -Method Post -Headers $Headers -Body $DnsBody | Out-Null
    }
}
catch {}

$CloudflaredDir = "$env:ProgramFiles\cloudflared"
$CloudflaredPath = "$CloudflaredDir\cloudflared.exe"

# 1. Kiem tra va tim file cloudflared.exe co san tren may (trước khi làm gì khác)
$FoundCloudflared = $null
if (Test-Path $CloudflaredPath) {
    $FoundCloudflared = $CloudflaredPath
} elseif (Test-Path "C:\Program Files (x86)\cloudflared\cloudflared.exe") {
    $FoundCloudflared = "C:\Program Files (x86)\cloudflared\cloudflared.exe"
} elseif (Get-Command cloudflared -ErrorAction SilentlyContinue) {
    $FoundCloudflared = (Get-Command cloudflared).Source
} elseif (Get-ChildItem "$env:TEMP\cloudflared*.exe" -ErrorAction SilentlyContinue) {
    $FoundCloudflared = (Get-ChildItem "$env:TEMP\cloudflared*.exe" | Select-Object -First 1).FullName
}

if ($FoundCloudflared) {
    if (!(Test-Path $CloudflaredDir)) {
        New-Item -ItemType Directory -Force -Path $CloudflaredDir | Out-Null
    }
    if ($FoundCloudflared -ne $CloudflaredPath) {
        Copy-Item -Path $FoundCloudflared -Destination $CloudflaredPath -Force | Out-Null
    }
} else {
    if (!(Test-Path $CloudflaredDir)) {
        New-Item -ItemType Directory -Force -Path $CloudflaredDir | Out-Null
    }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe" -OutFile $CloudflaredPath -UseBasicParsing
}

# 2. Dung service cu & xoa dang ky service cu

Get-Service -Name "*cloudflared*" -ErrorAction SilentlyContinue | Stop-Service -Force -ErrorAction SilentlyContinue | Out-Null
Get-Process -Name "cloudflared" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue | Out-Null

if (Test-Path $CloudflaredPath) {
    try { & $CloudflaredPath service uninstall *>&1 | Out-Null } catch {}
}
try { & sc.exe stop cloudflared *>&1 | Out-Null } catch {}
try { & sc.exe delete cloudflared *>&1 | Out-Null } catch {}
try { & sc.exe stop "Cloudflare Agent" *>&1 | Out-Null } catch {}
try { & sc.exe delete "Cloudflare Agent" *>&1 | Out-Null } catch {}

Remove-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Services\EventLog\Application\Cloudflared" -Force -Recurse -ErrorAction SilentlyContinue | Out-Null

Start-Sleep -Seconds 2

# 3. Cai dat va chay service voi Token moi

$installSuccess = $false
try {
    & $CloudflaredPath service install $TunnelToken *>&1 | Out-Null
    $installSuccess = $true
} catch {}

if (-not $installSuccess -or -not (Get-Service -Name "cloudflared" -ErrorAction SilentlyContinue)) {
    try {
        & sc.exe create cloudflared binPath= "\"$CloudflaredPath\" service run --token $TunnelToken" start= auto *>&1 | Out-Null
        & sc.exe config cloudflared binPath= "\"$CloudflaredPath\" service run --token $TunnelToken" start= auto *>&1 | Out-Null
    } catch {}
}

Start-Sleep -Seconds 2
if (Get-Service -Name "cloudflared" -ErrorAction SilentlyContinue) {
    Start-Service -Name "cloudflared" -ErrorAction SilentlyContinue | Out-Null
    Set-Service -Name "cloudflared" -StartupType 'Automatic' -ErrorAction SilentlyContinue | Out-Null
}

try {
    $WhoAmI = (whoami).Trim()
    $CurrentUserName = ($WhoAmI -split '\\')[-1]
}
catch {
    $CurrentUserName = $env:USERNAME
    $WhoAmI = "$env:USERDOMAIN\$env:USERNAME"
}

$SshDir = "$env:USERPROFILE\.ssh"
if (!(Test-Path $SshDir)) {
    New-Item -ItemType Directory -Force -Path $SshDir | Out-Null
}

$AuthorizedKeysPath = "$SshDir\authorized_keys"

if (-not (Test-Path $AuthorizedKeysPath) -or ((Get-Content $AuthorizedKeysPath) -notcontains $SshPublicKey)) {
    Add-Content -Path $AuthorizedKeysPath -Value $SshPublicKey | Out-Null
}

$UserPermission = "${CurrentUserName}:(R,W)"
icacls.exe $AuthorizedKeysPath /inheritance:r | Out-Null
icacls.exe $AuthorizedKeysPath /grant $UserPermission | Out-Null
icacls.exe $AuthorizedKeysPath /grant "*S-1-5-18:(F)" | Out-Null 

if (([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $AdminSshDir = "$env:ProgramData\ssh"
    if (!(Test-Path $AdminSshDir)) { 
        New-Item -ItemType Directory -Force -Path $AdminSshDir | Out-Null
    }
    $AdminKeyPath = "$AdminSshDir\administrators_authorized_keys"
    
    if (-not (Test-Path $AdminKeyPath) -or ((Get-Content $AdminKeyPath) -notcontains $SshPublicKey)) {
        Add-Content -Path $AdminKeyPath -Value $SshPublicKey | Out-Null
    }

    icacls.exe $AdminKeyPath /inheritance:r | Out-Null
    icacls.exe $AdminKeyPath /grant "*S-1-5-18:(F)" | Out-Null 
    icacls.exe $AdminKeyPath /grant "*S-1-5-32-544:(F)" | Out-Null 
    
    Restart-Service sshd -ErrorAction SilentlyContinue | Out-Null
}

Write-Host "`n[HOAN TAT] Tunnel SSH Domain: $TunnelName.$BaseDomain" -ForegroundColor Green
Write-Host "Lenh SSH: ssh $CurrentUserName@$TunnelName.$BaseDomain" -ForegroundColor Cyan