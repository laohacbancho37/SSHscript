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
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
# =========================================================================
# 🔴 CẤU HÌNH CÁ NHÂN (Vui lòng thay đổi các biến số này trước khi chạy) 🔴
# =========================================================================

$CloudflareAPIToken = "0a3c81d5682a02960a9783c6dfb22617314d8"
$CloudflareAccountId = "66ca9d4c586baabe040066154621c353"
$CloudflareZoneId = "b808f8b8eb32b2a826ad9b2600afc6ad"
$BaseDomain = "laohacbancho37.id.vn"

# Nội dung khóa Public Key của bạn lấy từ máy cá nhân (ID_RSA.PUB hoặc ID_ED25519.PUB)
$SshPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMk83rs0xpy8XOhogglSmppmkYenUEfMGdsGsGsebB29 laohacbancho37@A"

# =========================================================================


Write-Host "===========================================" -ForegroundColor Cyan
Write-Host "1. BẬT TÍNH NĂNG OPENSSH SERVER TRÊN WINDOWS" -ForegroundColor Cyan
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host "Kiểm tra trạng thái service OpenSSH Server (sshd)..."

$SshdFound = $false

if (Get-Service -Name sshd -ErrorAction SilentlyContinue) {
    Write-Host "-> Service OpenSSH Server đã được cài đặt, BỎ QUA BƯỚC TẢI!" -ForegroundColor Green
    $SshdFound = $true
} elseif (Test-Path "$env:ProgramFiles\OpenSSH-Win64\install-sshd.ps1") {
    Write-Host "-> Đã tìm thấy thư mục OpenSSH-Win64 trên máy, BỎ QUA BƯỚC TẢI!" -ForegroundColor Green
    $OpenSshDir = "$env:ProgramFiles\OpenSSH-Win64"
    Push-Location $OpenSshDir
    try {
        & powershell.exe -ExecutionPolicy Bypass -File "$OpenSshDir\install-sshd.ps1" | Out-Null
    } finally {
        Pop-Location
    }
    $SshdFound = $true
} elseif (Get-Command sshd -ErrorAction SilentlyContinue) {
    Write-Host "-> Đã tìm thấy lệnh sshd trên hệ thống, BỎ QUA BƯỚC TẢI!" -ForegroundColor Green
    $SshdFound = $true
} elseif (Test-Path "C:\Windows\System32\OpenSSH\sshd.exe") {
    Write-Host "-> Đã tìm thấy OpenSSH trong System32, BỎ QUA BƯỚC TẢI!" -ForegroundColor Green
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

Write-Host "Khởi động và cấu hình service sshd tự động bật cùng Windows..."
if (Get-Service -Name sshd -ErrorAction SilentlyContinue) {
    Start-Service sshd -ErrorAction SilentlyContinue
    Set-Service -Name sshd -StartupType 'Automatic' -ErrorAction SilentlyContinue
}

if (!(Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue | Select-Object Name, Enabled)) {
    Write-Host "Đang mở Firewall cho OpenSSH (Port 22 Inbound)..."
    New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
}

Write-Host "`n===========================================" -ForegroundColor Cyan
Write-Host "2. TƯƠNG TÁC VỚI CLOUDFLARE API" -ForegroundColor Cyan
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

# Tạo Secret ngẫu nhiên cho Tunnel (Cloudflare yều cầu 32 bytes base64 encoded)
$bytes = New-Object byte[] 32
$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$rng.GetBytes($bytes)
$TunnelSecret = [Convert]::ToBase64String($bytes)

# [2.1] Tạo Tunnel
Write-Host "-> Đang khởi tạo Tunnel [$TunnelName] qua API..."
$TunnelBody = @{
    name          = $TunnelName
    tunnel_secret = $TunnelSecret
    config_src    = "cloudflare"
} | ConvertTo-Json

try {
    $TunnelRes = Invoke-RestMethod -Uri "https://api.cloudflare.com/client/v4/accounts/$CloudflareAccountId/cfd_tunnel" -Method Post -Headers $Headers -Body $TunnelBody
    $TunnelId = $TunnelRes.result.id
    Write-Host "   => Thành công! Tunnel ID: $TunnelId" -ForegroundColor Green
}
catch {
    Write-Host "   => [LỖI] Không thể tạo Tunnel. Hãy chắc chắn API Token có quyền Account Zero Trust và Account ID đúng." -ForegroundColor Red
    Write-Host "   Chi tiết: $( $_.ErrorDetails.Message )"
    exit
}

# Lấy Token của Tunnel vừa khởi tạo
Write-Host "-> Đang lấy token dùng cho cloudflared service..."
try {
    $TokenRes = Invoke-RestMethod -Uri "https://api.cloudflare.com/client/v4/accounts/$CloudflareAccountId/cfd_tunnel/$TunnelId/token" -Method Get -Headers $Headers
    $TunnelToken = $TokenRes.result
}
catch {
    Write-Host "   => [LỖI] Không thể lấy token." -ForegroundColor Red
    exit
}

# [2.3.1] Cấu hình Tunnel Route / Zero Trust Ingress (map tới cổng ssh)
Write-Host "-> Cấu hình mapping (Zero Trust Ingress) về ssh://localhost:22..."
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
    Write-Host "   => Đã cấu hình Ingress Rule thành công" -ForegroundColor Green
}
catch {
    Write-Host "   => [CẢNH BÁO] Không thể thiết lập cấu hình Tunnel Ingress." -ForegroundColor Yellow
}

# [2.3.2] Tạo CNAME DNS trong Zero Trust Domain
Write-Host "-> Tạo DNS Record (CNAME: $TunnelName.$BaseDomain => $TunnelId.cfargotunnel.com)..."
$DnsBody = @{
    type    = "CNAME"
    name    = $TunnelName
    content = "$TunnelId.cfargotunnel.com"
    proxied = $true
} | ConvertTo-Json

try {
    Invoke-RestMethod -Uri "https://api.cloudflare.com/client/v4/zones/$CloudflareZoneId/dns_records" -Method Post -Headers $Headers -Body $DnsBody | Out-Null
    Write-Host "   => Hoàn tất tạo DNS CNAME Record." -ForegroundColor Green
}
catch {
    Write-Host "   => [CẢNH BÁO] Không thể tạo DNS Record, có thể record này đã tồn tại." -ForegroundColor Yellow
}

Write-Host "`n===========================================" -ForegroundColor Cyan
Write-Host "3. TẢI VÀ INSTALL CLOUDFLARED SERVICE" -ForegroundColor Cyan
Write-Host "===========================================" -ForegroundColor Cyan

$CloudflaredDir = "$env:ProgramFiles\cloudflared"
$CloudflaredPath = "$CloudflaredDir\cloudflared.exe"

# 1. Kiểm tra và tìm file cloudflared.exe có sẵn trên máy (trước khi làm gì khác)
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
    Write-Host "-> Đã tìm thấy cloudflared.exe tại [$FoundCloudflared], BỎ QUA BƯỚC TẢI VỀ!" -ForegroundColor Green
    if (!(Test-Path $CloudflaredDir)) {
        New-Item -ItemType Directory -Force -Path $CloudflaredDir | Out-Null
    }
    if ($FoundCloudflared -ne $CloudflaredPath) {
        Copy-Item -Path $FoundCloudflared -Destination $CloudflaredPath -Force
    }
} else {
    Write-Host "-> Không tìm thấy cloudflared.exe trên máy, đang tải về file mới..." -ForegroundColor Yellow
    if (!(Test-Path $CloudflaredDir)) {
        New-Item -ItemType Directory -Force -Path $CloudflaredDir | Out-Null
    }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe" -OutFile $CloudflaredPath -UseBasicParsing
}

# 2. Dừng service cũ & xóa đăng ký service cũ
Write-Host "Đang dừng và cập nhật service cloudflared sang Token mới..." -ForegroundColor Yellow
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

# 3. Cài đặt và chạy service với Token mới
Write-Host "Đang cài đặt và kích hoạt service cloudflared với Token mới..." -ForegroundColor Cyan
& $CloudflaredPath service install $TunnelToken

Start-Sleep -Seconds 2
if (Get-Service -Name "cloudflared" -ErrorAction SilentlyContinue) {
    Start-Service -Name "cloudflared" -ErrorAction SilentlyContinue
    Set-Service -Name "cloudflared" -StartupType 'Automatic' -ErrorAction SilentlyContinue
    Write-Host "-> Service cloudflared đã được khởi chạy thành công với Token mới!" -ForegroundColor Green
} else {
    Write-Host "-> [CẢNH BÁO] Không tìm thấy service cloudflared sau khi install." -ForegroundColor Yellow
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
Write-Host "Gắn Public Key của bạn vào hệ thống cấu hình SSH Windows..."

# Windows OpenSSH yêu cầu việc phân quyền cho file key vô cùng khắt khe
$SshDir = "$env:USERPROFILE\.ssh"
if (!(Test-Path $SshDir)) {
    New-Item -ItemType Directory -Force -Path $SshDir | Out-Null
}

$AuthorizedKeysPath = "$SshDir\authorized_keys"

if (-not (Test-Path $AuthorizedKeysPath) -or ((Get-Content $AuthorizedKeysPath) -notcontains $SshPublicKey)) {
    Add-Content -Path $AuthorizedKeysPath -Value $SshPublicKey
}

# Cấp quyền cứng cho Standard user bằng SID để tương thích mọi ngôn ngữ Windows
icacls.exe $AuthorizedKeysPath /inheritance:r | Out-Null
$UserPermission = "${CurrentUserName}:(R,W)"
icacls.exe $AuthorizedKeysPath /grant $UserPermission | Out-Null
icacls.exe $AuthorizedKeysPath /grant "*S-1-5-18:(F)" | Out-Null # S-1-5-18 là NT AUTHORITY\SYSTEM

# Kiểm tra nếu đăng nhập User dưới dạng hệ thống Administrator thì File lưu keys phải được ném sang ProgramData 
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

    # Phân quyền chặt chẽ cho folder ProgramData Administrator Auth Key (dùng SID)
    icacls.exe $AdminKeyPath /inheritance:r | Out-Null
    icacls.exe $AdminKeyPath /grant "*S-1-5-18:(F)" | Out-Null # SYSTEM
    icacls.exe $AdminKeyPath /grant "*S-1-5-32-544:(F)" | Out-Null # Administrators
    
    # Restart lại dịch vụ SSH để nạp các ACL
    Restart-Service sshd -ErrorAction SilentlyContinue
}

Write-Host "`n===========================================" -ForegroundColor Green
Write-Host "[HOÀN TẤT] MÁY KHÁCH ĐÃ ĐƯỢC CẤU HÌNH THÀNH CÔNG!" -ForegroundColor Green
Write-Host "===========================================" -ForegroundColor Green
Write-Host "Từ bây giờ, bạn có thể ssh từ máy tính của bạn về máy khách mà không cần mở port mạng."
Write-Host "Username kết nối (whoami): $CurrentUserName" -ForegroundColor Yellow
Write-Host "Lệnh SSH trực tiếp từ máy cá nhân:" -ForegroundColor Cyan
Write-Host "   ssh $CurrentUserName@$TunnelName.$BaseDomain" -ForegroundColor Green
Write-Host "`nBạn thao tác tiếp bên máy cá nhân, thêm cấu hình ProxyCommand."

Write-Host "`nNhấn phím bất kỳ để thoát..." -ForegroundColor Cyan
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
