<# :
@echo off
setlocal
cd /d "%~dp0"

:: Kiem tra quyen Administrator
net session >nul 2>&1
if NOT "%errorLevel%" == "0" (
    echo [*] Xin cap quyen Administrator. Vui long chon "Yes" bang thong bao tiep theo...
    powershell -NoProfile -Command "Start-Process cmd -ArgumentList '/c `\"%~f0`\"' -Verb RunAs"
    exit /b
)

:: Mo bang PowerShell tu bypass chinh sach
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression -Command (Get-Content -LiteralPath '%~f0' -Raw -Encoding UTF8)"
pause
exit /b
#>

# =========================================================================
# Bắt đầu không gian mã nguồn chạy bằng môi trường PowerShell bên dưới
# =========================================================================

# Đã có lệnh thay đổi thư mục làm việc (CD) ở ngay trên phần BATCH header

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
    Write-Host "`nNhan phim bat ky de thoat..." -ForegroundColor Cyan
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
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
$SshdFound = $false

if (Get-Service -Name sshd -ErrorAction SilentlyContinue) {
    Write-Host "-> Service OpenSSH Server da duoc cai dat, BO QUA BUOC TAI!" -ForegroundColor Green
    $SshdFound = $true
} elseif (Test-Path "$env:ProgramFiles\OpenSSH-Win64\install-sshd.ps1") {
    Write-Host "-> Da tim thay thu muc OpenSSH-Win64 tren may, BO QUA BUOC TAI!" -ForegroundColor Green
    $OpenSshDir = "$env:ProgramFiles\OpenSSH-Win64"
    Push-Location $OpenSshDir
    try {
        & powershell.exe -ExecutionPolicy Bypass -File "$OpenSshDir\install-sshd.ps1" | Out-Null
    } finally {
        Pop-Location
    }
    $SshdFound = $true
} elseif (Get-Command sshd -ErrorAction SilentlyContinue) {
    Write-Host "-> Da tim thay lenh sshd tren he thong, BO QUA BUOC TAI!" -ForegroundColor Green
    $SshdFound = $true
} elseif (Test-Path "C:\Windows\System32\OpenSSH\sshd.exe") {
    Write-Host "-> Da tim thay OpenSSH trong System32, BO QUA BUOC TAI!" -ForegroundColor Green
    $SshdFound = $true
}

if (-not $SshdFound) {
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

$Headers = @{
    "Authorization" = "Bearer $CloudflareAPIToken"
    "Content-Type"  = "application/json"
}

Write-Host "-> Đang kiểm tra danh sách Tunnel hiện có trên Cloudflare để xử lý cấp tên..."
try {
    $TunnelsRes = Invoke-RestMethod -Uri "https://api.cloudflare.com/client/v4/accounts/$CloudflareAccountId/cfd_tunnel?is_deleted=false&per_page=100" -Method Get -Headers $Headers
    $ExistingTunnels = @($TunnelsRes.result.name)
} catch {
    $ExistingTunnels = @()
    Write-Host "   [CẢNH BÁO] Không thể lấy danh sách tunnel để kiểm tra trùng lặp." -ForegroundColor Yellow
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

if ($TunnelName -ne $InputName) {
    Write-Host "-> Tên [$InputName] từ whoami đã tồn tại, tự động đổi thành: $TunnelName" -ForegroundColor Yellow
} else {
    Write-Host "-> Tự động đặt tên Tunnel theo whoami: $TunnelName" -ForegroundColor Green
}

# Đã dời block Header lên trên cùng để tiện gọi listAPI rồi

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
} catch {
    Write-Host "   => [LOI] Khong the tao Tunnel. Hay chac chan API Token co quyen Account Zero Trust va Account ID dung." -ForegroundColor Red
    Write-Host "   Chi tiet: $( $_.ErrorDetails.Message )"
    exit
}

# Lay Token Tunnel
Write-Host "-> Dang lay token dung cho cloudflared service..."
try {
    $TokenRes = Invoke-RestMethod -Uri "https://api.cloudflare.com/client/v4/accounts/$CloudflareAccountId/cfd_tunnel/$TunnelId/token" -Method Get -Headers $Headers
    $TunnelToken = $TokenRes.result
} catch {
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
} catch {
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
} catch {
    Write-Host "   => [CANH BAO] Khong the tao DNS Record, co the record nay da ton tai." -ForegroundColor Yellow
}

Write-Host "`n===========================================" -ForegroundColor Cyan
Write-Host "3. TAI VA INSTALL CLOUDFLARED SERVICE" -ForegroundColor Cyan
Write-Host "===========================================" -ForegroundColor Cyan

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
    Write-Host "-> Da tim thay cloudflared.exe tai [$FoundCloudflared], BO QUA BUOC TAI VE!" -ForegroundColor Green
    if (!(Test-Path $CloudflaredDir)) {
        New-Item -ItemType Directory -Force -Path $CloudflaredDir | Out-Null
    }
    if ($FoundCloudflared -ne $CloudflaredPath) {
        Copy-Item -Path $FoundCloudflared -Destination $CloudflaredPath -Force
    }
} else {
    Write-Host "-> Khong tim thay cloudflared.exe tren may, dang tai ve file moi..." -ForegroundColor Yellow
    if (!(Test-Path $CloudflaredDir)) {
        New-Item -ItemType Directory -Force -Path $CloudflaredDir | Out-Null
    }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe" -OutFile $CloudflaredPath -UseBasicParsing
}

# 2. Dung service cu & xoa dang ky service cu
Write-Host "Dang dung va cap nhat service cloudflared sang Token moi..." -ForegroundColor Yellow
Get-Service -Name "*cloudflared*" -ErrorAction SilentlyContinue | Stop-Service -Force -ErrorAction SilentlyContinue
Get-Process -Name "cloudflared" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

if (Test-Path $CloudflaredPath) {
    try { & $CloudflaredPath service uninstall *>&1 | Out-Null } catch {}
}
try { & sc.exe stop cloudflared *>&1 | Out-Null } catch {}
try { & sc.exe delete cloudflared *>&1 | Out-Null } catch {}
try { & sc.exe stop "Cloudflare Agent" *>&1 | Out-Null } catch {}
try { & sc.exe delete "Cloudflare Agent" *>&1 | Out-Null } catch {}

Remove-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Services\EventLog\Application\Cloudflared" -Force -Recurse -ErrorAction SilentlyContinue

Start-Sleep -Seconds 2

# 3. Cai dat va chay service voi Token moi
Write-Host "Dang cai dat va kich hoat service cloudflared voi Token moi..." -ForegroundColor Cyan
& $CloudflaredPath service install $TunnelToken

Start-Sleep -Seconds 2
if (Get-Service -Name "cloudflared" -ErrorAction SilentlyContinue) {
    Start-Service -Name "cloudflared" -ErrorAction SilentlyContinue
    Set-Service -Name "cloudflared" -StartupType 'Automatic' -ErrorAction SilentlyContinue
    Write-Host "-> Service cloudflared da duoc khoi chay thanh cong voi Token moi!" -ForegroundColor Green
} else {
    Write-Host "-> [CANH BAO] Khong tim thay service cloudflared sau khi install." -ForegroundColor Yellow
}

Write-Host "`n===========================================" -ForegroundColor Cyan
Write-Host "4. TỰ ĐỘNG LẤY TÊN USER HỆ THỐNG (WHOAMI)" -ForegroundColor Cyan
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host "Đang chạy lệnh whoami để lấy tên User đăng nhập..."

try {
    $WhoAmI = (whoami).Trim()
    $CurrentUserName = ($WhoAmI -split '\\')[-1]
}
catch {
    $CurrentUserName = $env:USERNAME
    $WhoAmI = "$env:USERDOMAIN\$env:USERNAME"
}

Write-Host "-> User hệ thống (whoami): $WhoAmI" -ForegroundColor Green
Write-Host "-> Username kết nối SSH: $CurrentUserName" -ForegroundColor Green

Write-Host "`n===========================================" -ForegroundColor Cyan
Write-Host "5. CẤU HÌNH SSH AUTHORIZED KEYS" -ForegroundColor Cyan
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host "Gán Public Key của bạn vào hệ thống SSH Windows..."

$SshDir = "$env:USERPROFILE\.ssh"
if (!(Test-Path $SshDir)) {
    New-Item -ItemType Directory -Force -Path $SshDir | Out-Null
}

$AuthorizedKeysPath = "$SshDir\authorized_keys"

if (-not (Test-Path $AuthorizedKeysPath) -or ((Get-Content $AuthorizedKeysPath) -notcontains $SshPublicKey)) {
    Add-Content -Path $AuthorizedKeysPath -Value $SshPublicKey
}

# Cấp quyền cho Standard user
icacls.exe $AuthorizedKeysPath /inheritance:r | Out-Null
$UserPermission = "${CurrentUserName}:(R,W)"
icacls.exe $AuthorizedKeysPath /grant $UserPermission | Out-Null
icacls.exe $AuthorizedKeysPath /grant "*S-1-5-18:(F)" | Out-Null 

if (([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Do máy nằm trong quyền Administrator Server, khóa tự động clone vào ProgramData/ssh..."
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
Write-Host "[HOÀN TẤT] MÁY KHÁCH ĐÃ ĐƯỢC CẤU HÌNH THÀNH CÔNG!" -ForegroundColor Green
Write-Host "===========================================" -ForegroundColor Green
Write-Host "Từ bây giờ, bạn có thể SSH từ máy tính của bạn về máy khách mà không cần mở port mạng."
Write-Host "Username kết nối (whoami): $CurrentUserName" -ForegroundColor Yellow
Write-Host "Lệnh SSH trực tiếp từ máy cá nhân:" -ForegroundColor Cyan
Write-Host "   ssh $CurrentUserName@$TunnelName.$BaseDomain" -ForegroundColor Green
Write-Host "`nBạn thao tác tiếp bên máy cá nhân, thêm cấu hình ProxyCommand."

Write-Host "`nNhan phim bat ky de thoat..." -ForegroundColor Cyan
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
