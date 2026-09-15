$ErrorActionPreference = 'Stop'

function Find-Keytool {
    $candidates = @(
        'keytool',
        "$env:ProgramFiles\Android\Android Studio\jbr\bin\keytool.exe",
        "$env:ProgramFiles\Android\Android Studio\jre\bin\keytool.exe",
        "$env:JAVA_HOME\bin\keytool.exe"
    )
    foreach ($candidate in $candidates) {
        if (-not $candidate) { continue }
        try {
            $command = Get-Command $candidate -ErrorAction Stop
            return $command.Source
        } catch {}
        if (Test-Path $candidate) { return $candidate }
    }
    throw 'keytool پیدا نشد. Android Studio یا Java JDK را نصب کن و دوباره اجرا کن.'
}

function Read-PlainSecret([string]$Prompt) {
    $secure = Read-Host $Prompt -AsSecureString
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
    }
}

$keytool = Find-Keytool
$outDir = Join-Path $HOME 'VELIXEO-signing'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$keystore = Join-Path $outDir 'velixeo-release.jks'
$base64File = Join-Path $outDir 'velixeo-release.base64.txt'
$shaFile = Join-Path $outDir 'VELIXEO-SHA1.txt'
$alias = 'velixeo'

if (Test-Path $keystore) {
    Write-Host "Keystore از قبل وجود دارد: $keystore" -ForegroundColor Yellow
    Write-Host 'برای جلوگیری از تغییر کلید امضای اپ، فایل قبلی overwrite نمی‌شود.' -ForegroundColor Yellow
    exit 2
}

$storePassword = Read-PlainSecret 'یک رمز قوی برای Keystore وارد کن'
if ($storePassword.Length -lt 8) { throw 'رمز Keystore باید حداقل 8 کاراکتر باشد.' }
$keyPassword = Read-PlainSecret 'رمز Key را وارد کن (می‌تواند همان رمز Keystore باشد)'
if ($keyPassword.Length -lt 8) { throw 'رمز Key باید حداقل 8 کاراکتر باشد.' }

& $keytool -genkeypair -v `
    -keystore $keystore `
    -alias $alias `
    -keyalg RSA `
    -keysize 2048 `
    -validity 10000 `
    -storepass $storePassword `
    -keypass $keyPassword `
    -dname 'CN=VELIXEO, OU=Mobile, O=VELIXEO, C=AF'
if ($LASTEXITCODE -ne 0) { throw 'ساخت Keystore ناموفق بود.' }

[Convert]::ToBase64String([IO.File]::ReadAllBytes($keystore)) | Set-Content -NoNewline -Encoding ascii $base64File
$details = & $keytool -list -v -keystore $keystore -alias $alias -storepass $storePassword
$shaLine = $details | Where-Object { $_ -match 'SHA1:|SHA-1:' } | Select-Object -First 1
$shaLine | Set-Content -Encoding utf8 $shaFile

Write-Host ''
Write-Host 'VELIXEO release signing key created.' -ForegroundColor Green
Write-Host "Keystore: $keystore"
Write-Host "Base64 for GitHub Secret: $base64File"
Write-Host "Alias: $alias"
Write-Host "Signing fingerprint: $shaLine" -ForegroundColor Cyan
Write-Host ''
Write-Host 'مهم: فایل JKS، Base64 و رمزها را برای هیچ‌کس ارسال نکن و یک Backup امن نگه دار.' -ForegroundColor Yellow
Write-Host 'فقط SHA-1 را می‌توانی برای تنظیم Google OAuth استفاده کنی.' -ForegroundColor Yellow
