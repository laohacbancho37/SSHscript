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
Write-Host "1. BẬT TÍNH NĂNG OPENSSH SERVER TRÊN WINDOWS" -ForegroundColor Cyan
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host "Kiem tra trang thai service OpenSSH Server (sshd) tren may..."
if (Get-Service -Name sshd -ErrorAction SilentlyContinue) {
    Write-Host "-> Service OpenSSH Server da duoc cai dat." -ForegroundColor Green
}
elseif (Test-Path "$env:ProgramFiles\OpenSSH-Win64\install-sshd.ps1") {
    Write-Host "-> Da tim thay thu muc OpenSSH-Win64 tren may, bo qua buoc tai!" -ForegroundColor Green
    $OpenSshDir = "$env:ProgramFiles\OpenSSH-Win64"
    Push-Location $OpenSshDir
    try {
        & powershell.exe -ExecutionPolicy Bypass -File "$OpenSshDir\install-sshd.ps1" | Out-Null
    } finally {
        Pop-Location
    }
}
elseif (Get-Command sshd -ErrorAction SilentlyContinue) {
    Write-Host "-> Da tim thay lenh sshd tren he thong, bo qua buoc tai!" -ForegroundColor Green
}
else {
    Write-Host "Đang tải và cài đặt OpenSSH Service phiên bản mới nhất từ GitHub..."
    $ZipPath = "$env:TEMP\OpenSSH-Win64.zip"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri "https://github.com/PowerShell/Win32-OpenSSH/releases/download/v9.5.0.0p1-Beta/OpenSSH-Win64.zip" -OutFile $ZipPath -UseBasicParsing
    
    Write-Host "Đang giải nén OpenSSH..."
    Expand-Archive -Path $ZipPath -DestinationPath $env:ProgramFiles -Force
    $OpenSshDir = "$env:ProgramFiles\OpenSSH-Win64"
    
    Write-Host "Cài đặt service sshd..."
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

    Write-Host "Sửa quyền File Host Key..."
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
    
    Write-Host "Thiết lập PowerShell làm Default Shell..."
    if (!(Test-Path "HKLM:\SOFTWARE\OpenSSH")) { New-Item -Path "HKLM:\SOFTWARE\OpenSSH" -Force -ErrorAction SilentlyContinue | Out-Null }
    New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell -Value "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
}

Write-Host "Khoi dong va cau hinh service sshd tu dong bat cung Windows..."
if (Get-Service -Name sshd -ErrorAction SilentlyContinue) {
    Start-Service sshd -ErrorAction SilentlyContinue
    Set-Service -Name sshd -StartupType 'Automatic' -ErrorAction SilentlyContinue
}

if (!(Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue | Select-Object Name, Enabled)) {
    Write-Host "Dang mo Firewall cho OpenSSH (Port 22 Inbound)..."
    New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
}

Write-Host "`n===========================================" -ForegroundColor Cyan
Write-Host "2. TUONG TAC VOI CLOUDFLARE API" -ForegroundColor Cyan
Write-Host "===========================================" -ForegroundColor Cyan

$InputName = Read-Host "Nhập tên Tunnel phụ domain (Để trống máy sẽ tự động tìm tên ssh00X chưa được cấp)"

$Headers = @{
    "Authorization" = "Bearer $CloudflareAPIToken"
    "Content-Type"  = "application/json"
}

Write-Host "-> Đang kiểm tra danh sách Tunnel hiện có trên Cloudflare để xử lý cấp tên..."
try {
    $TunnelsRes = Invoke-RestMethod -Uri "https://api.cloudflare.com/client/v4/accounts/$CloudflareAccountId/cfd_tunnel?is_deleted=false&per_page=100" -Method Get -Headers $Headers
    $ExistingTunnels = @($TunnelsRes.result.name)
}
catch {
    $ExistingTunnels = @()
    Write-Host "   [CẢNH BÁO] Không thể lấy danh sách tunnel để kiểm tra trùng lặp." -ForegroundColor Yellow
}

if ([string]::IsNullOrWhiteSpace($InputName)) {
    $i = 1
    do {
        $TunnelName = "ssh{0:D3}" -f $i
        $i++
    } while ($ExistingTunnels -contains $TunnelName)
    Write-Host "-> Để trống tên, hệ thống tự cấp: $TunnelName" -ForegroundColor Green
}
else {
    $TunnelName = $InputName
    $i = 1
    while ($ExistingTunnels -contains $TunnelName) {
        $TunnelName = "$InputName$i"
        $i++
    }
    if ($TunnelName -ne $InputName) {
        Write-Host "-> Tên [$InputName] đã tồn tại, tự động đổi thành: $TunnelName" -ForegroundColor Yellow
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
Write-Host "-> Dang khoi tao Tunnel [$TunnelName] qua API..."
$TunnelBody = @{
    name          = $TunnelName
    tunnel_secret = $TunnelSecret
    config_src    = "cloudflare"
} | ConvertTo-Json

try {
    $TunnelRes = Invoke-RestMethod -Uri "https://api.cloudflare.com/client/v4/accounts/$CloudflareAccountId/cfd_tunnel" -Method Post -Headers $Headers -Body $TunnelBody
    $TunnelId = $TunnelRes.result.id
    Write-Host "   => Thanh cong! Tunnel ID: $TunnelId" -ForegroundColor Green
}
catch {
    Write-Host "   => [LOI] Khong the tao Tunnel. Hay chac chan API Token co quyen Account Zero Trust va Account ID dung." -ForegroundColor Red
    Write-Host "   Chi tiet: $( $_.ErrorDetails.Message )"
    exit
}

# Lay Token Tunnel
Write-Host "-> Dang lay token dung cho cloudflared service..."
try {
    $TokenRes = Invoke-RestMethod -Uri "https://api.cloudflare.com/client/v4/accounts/$CloudflareAccountId/cfd_tunnel/$TunnelId/token" -Method Get -Headers $Headers
    $TunnelToken = $TokenRes.result
}
catch {
    Write-Host "   => [LOI] Khong the lay token." -ForegroundColor Red
    exit
}

# [2.3.1] Cau hinh Tunnel Route 
Write-Host "-> Cau hinh mapping (Zero Trust Ingress) ve ssh://localhost:22..."
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
    Write-Host "   => Da cau hinh Ingress Rule thanh cong" -ForegroundColor Green
}
catch {
    Write-Host "   => [CANH BAO] Khong the thiet lap cau hinh Tunnel Ingress." -ForegroundColor Yellow
}

# [2.3.2] Tao CNAME DNS 
Write-Host "-> Tao DNS Record (CNAME: $TunnelName.$BaseDomain => $TunnelId.cfargotunnel.com)..."
$DnsBody = @{
    type    = "CNAME"
    name    = $TunnelName
    content = "$TunnelId.cfargotunnel.com"
    proxied = $true
} | ConvertTo-Json

try {
    Invoke-RestMethod -Uri "https://api.cloudflare.com/client/v4/zones/$CloudflareZoneId/dns_records" -Method Post -Headers $Headers -Body $DnsBody | Out-Null
    Write-Host "   => Hoan tat tao DNS CNAME Record." -ForegroundColor Green
}
catch {
    Write-Host "   => [CANH BAO] Khong the tao DNS Record, co the record nay da ton tai." -ForegroundColor Yellow
}

Write-Host "`n===========================================" -ForegroundColor Cyan
Write-Host "3. TAI VA INSTALL CLOUDFLARED SERVICE" -ForegroundColor Cyan
Write-Host "===========================================" -ForegroundColor Cyan

Write-Host "Kiem tra va dung cac dich vu / tien trinh cloudflared cu neu dang chay..."

# Dung Tat ca service va process cloudflared
Get-Service -Name "*cloudflared*" -ErrorAction SilentlyContinue | Stop-Service -Force -ErrorAction SilentlyContinue
Get-Process -Name "cloudflared" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

# Thu muc co dinh luu cloudflared.exe (tranh luu trong TEMP bi xoa gay loi service)
$CloudflaredDir = "$env:ProgramFiles\cloudflared"
if (!(Test-Path $CloudflaredDir)) {
    New-Item -ItemType Directory -Force -Path $CloudflaredDir | Out-Null
}
$CloudflaredPath = "$CloudflaredDir\cloudflared.exe"

# Go bo service cu qua cloudflared service uninstall VA sc.exe delete
if (Test-Path $CloudflaredPath) {
    try { & $CloudflaredPath service uninstall *>&1 | Out-Null } catch {}
}
try { & sc.exe stop cloudflared *>&1 | Out-Null } catch {}
try { & sc.exe delete cloudflared *>&1 | Out-Null } catch {}
try { & sc.exe stop "Cloudflare Agent" *>&1 | Out-Null } catch {}
try { & sc.exe delete "Cloudflare Agent" *>&1 | Out-Null } catch {}

Remove-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Services\EventLog\Application\Cloudflared" -Force -Recurse -ErrorAction SilentlyContinue

Start-Sleep -Seconds 2

# Tai cloudflared.exe moi nhat vao thu muc co dinh (neu chưa có)
if (Test-Path $CloudflaredPath) {
    Write-Host "-> Da tim thay cloudflared.exe tai [$CloudflaredPath], bo qua buoc tai!" -ForegroundColor Green
}
elseif (Test-Path "C:\Program Files (x86)\cloudflared\cloudflared.exe") {
    Write-Host "-> Da tim thay cloudflared.exe trong Program Files (x86), dang sao chep..." -ForegroundColor Green
    Copy-Item -Path "C:\Program Files (x86)\cloudflared\cloudflared.exe" -Destination $CloudflaredPath -Force
}
elseif (Get-Command cloudflared -ErrorAction SilentlyContinue) {
    $existingCmd = (Get-Command cloudflared).Source
    Write-Host "-> Da tim thay cloudflared tai [$existingCmd], dang sao chep..." -ForegroundColor Green
    Copy-Item -Path $existingCmd -Destination $CloudflaredPath -Force
}
else {
    Write-Host "Dang tai ve cloudflared-windows-amd64.exe moi nhat..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe" -OutFile $CloudflaredPath -UseBasicParsing
}

# Cai dat service cloudflared moi voi token
Write-Host "Dang cai dat service cloudflared moi..."
& $CloudflaredPath service install $TunnelToken

Start-Sleep -Seconds 2
if (Get-Service -Name "cloudflared" -ErrorAction SilentlyContinue) {
    Start-Service -Name "cloudflared" -ErrorAction SilentlyContinue
    Set-Service -Name "cloudflared" -StartupType 'Automatic' -ErrorAction SilentlyContinue
    Write-Host "-> Service cloudflared da duoc khoi chay thanh cong!" -ForegroundColor Green
} else {
    Write-Host "-> [CANH BAO] Khong tim me service cloudflared sau khi install." -ForegroundColor Yellow
}

Write-Host "`n===========================================" -ForegroundColor Cyan
Write-Host "4. CAU HINH SSH AUTHORIZED KEYS" -ForegroundColor Cyan
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host "Gan Public Key cua ban vao he thong SSH Windows..."

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
$UserPermission = "$env:USERNAME:(R,W)"
icacls.exe $AuthorizedKeysPath /grant $UserPermission | Out-Null
icacls.exe $AuthorizedKeysPath /grant "*S-1-5-18:(F)" | Out-Null 

if (([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Do may nam trong quyen Administrator Server, khoa tu dong clone vao ProgramData/ssh..."
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
    
    Restart-Service sshd -ErrorAction SilentlyContinue
}

Write-Host "`n===========================================" -ForegroundColor Green
Write-Host "[HOAN TAT] MAY KHACH DA DUOC CAU HINH THANH CONG!" -ForegroundColor Green
Write-Host "===========================================" -ForegroundColor Green
Write-Host "Tu bay gio, ban co thi ssh tu may tinh cua ban ve may khach ma khong can mo port mang."
Write-Host "Ban thao tac tiep ben may ca nhan, them cau hinh ProxyCommand."

Write-Host "`nNhan phim bat ky de thoat..." -ForegroundColor Cyan
try {
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}
catch {
    # Fileless execution hoac console khong the doc phim
    Start-Sleep -Seconds 10
}