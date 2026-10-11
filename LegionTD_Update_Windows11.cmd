@echo off
setlocal
 title Legion TD updater
set "LEGIONTD_UPDATER_SELF=%~f0"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -NoExit -ExecutionPolicy Bypass -Command "$text = [IO.File]::ReadAllText($env:LEGIONTD_UPDATER_SELF, [Text.Encoding]::UTF8); $marker = '# POWERSHELL_PAYLOAD'; $body = $text.Substring($text.LastIndexOf($marker) + $marker.Length); & ([scriptblock]::Create($body))"
echo.
echo Close this window using X.
"%ComSpec%" /d /k
exit /b
# POWERSHELL_PAYLOAD
$ErrorActionPreference = "Stop"
$TempDir = $null
$TempInstall = $null
$LogFile = Join-Path ([System.IO.Path]::GetTempPath()) "LegionTD-updater-error.log"

try {
    # Enable TLS 1.2 for older Windows PowerShell configurations.
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    $Repo = "team-oze/Legion-TD"
    $Api = "https://api.github.com/repos/$Repo/releases/latest"
    
    # Враховує стандартну папку Documents, навіть якщо вона перенесена.
    $Documents = [Environment]::GetFolderPath("MyDocuments")
    if ([string]::IsNullOrWhiteSpace($Documents)) {
        throw "Не вдалося визначити папку Documents для поточного користувача."
    }
    $MapDir = Join-Path $Documents "Warcraft III\Maps\Download"
    
    $TempDir = Join-Path ([System.IO.Path]::GetTempPath()) (
        "LegionTD-" + [guid]::NewGuid().ToString("N")
    )

    Write-Host "=== Legion TD updater ===" -ForegroundColor Cyan
    Write-Host "Отримую інформацію про останній реліз..."

    $Headers = @{
        "User-Agent" = "LegionTD-Updater"
        Accept = "application/vnd.github+json"
        "X-GitHub-Api-Version" = "2022-11-28"
    }

    $Release = Invoke-RestMethod -Uri $Api -Headers $Headers -TimeoutSec 60

    $Assets = @(
        $Release.assets |
        Where-Object {
            $_.name -match '\.(w3x|w3m)$'
        } |
        Sort-Object `
            @{ Expression = { if ($_.name -match '\.w3x$') { 0 } else { 1 } } }, `
            @{ Expression = { if ($_.name -match 'legion') { 0 } else { 1 } } }, `
            @{ Expression = { $_.name.ToLowerInvariant() } }
    )

    if ($Assets.Count -eq 0) {
        throw "У релізі не знайдено файл .w3x або .w3m."
    }

    $Asset = $Assets[0]
    $FileName = $Asset.name
    if ([IO.Path]::GetFileName($FileName) -ne $FileName -or
        $FileName.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) {
        throw "Некоректна назва файлу карти у релізі."
    }
    $Destination = Join-Path $MapDir $FileName

    Write-Host "Реліз: $($Release.tag_name)"
    Write-Host "Файл: $FileName"

    New-Item -ItemType Directory -Force -Path $MapDir |
        Out-Null
    New-Item -ItemType Directory -Force -Path $TempDir |
        Out-Null

    $TempFile = Join-Path $TempDir $FileName
    $TempInstall = "$Destination.new"

    Write-Host "Завантажую карту..."

    Invoke-WebRequest `
        -UseBasicParsing `
        -Headers @{ "User-Agent" = "LegionTD-Updater" } `
        -TimeoutSec 300 `
        -Uri $Asset.browser_download_url `
        -OutFile $TempFile

    if (!(Test-Path $TempFile) -or
        (Get-Item $TempFile).Length -eq 0) {
        throw "Завантажений файл порожній."
    }

    $Install = $true

    if (Test-Path $Destination) {
        $OldHash = (Get-FileHash $Destination -Algorithm SHA256).Hash
        $NewHash = (Get-FileHash $TempFile -Algorithm SHA256).Hash

        if ($OldHash -eq $NewHash) {
            Write-Host "Вже встановлена актуальна версія." `
                -ForegroundColor Green
            $Install = $false
        }
    }

    if ($Install) {
        # Не перезаписуємо карту частково завантаженим файлом.
        Copy-Item -LiteralPath $TempFile -Destination $TempInstall -Force
        Move-Item -LiteralPath $TempInstall -Destination $Destination -Force

        Write-Host "Карту оновлено!" -ForegroundColor Green
        Write-Host "Шлях: $Destination"
    }
}
catch {
    Write-Host "Помилка: $($_.Exception.Message)" -ForegroundColor Red
    try {
        ($_ | Format-List * -Force | Out-String) |
            Set-Content -LiteralPath $LogFile -Encoding UTF8
        Write-Host "Подробиці помилки: $LogFile" -ForegroundColor Yellow
    }
    catch {
        Write-Host "Не вдалося зберегти журнал помилки." -ForegroundColor Yellow
    }
}
finally {
    if ($TempDir) {
        Remove-Item -LiteralPath $TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($TempInstall) {
        Remove-Item -LiteralPath $TempInstall -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ""
Write-Host "Роботу завершено. Щоб закрити вікно, натисніть X у його куті." -ForegroundColor Cyan
