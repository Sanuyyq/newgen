#Requires -Version 5.1
<#
.SYNOPSIS
    Одной кнопкой ставит Git + Visual Studio 2022 Build Tools + Flutter SDK
    и собирает negern.exe.

.DESCRIPTION
    Первый запуск: ~45-90 минут и ~12 GB диска (VS Build Tools — самая
    тяжёлая часть).
    Последующие запуски: 1-3 минуты.

    Запускать от ИМЕНИ АДМИНИСТРАТОРА (ПКМ → Запустить от имени администратора),
    иначе winget не сможет установить Visual Studio Build Tools.

.EXAMPLE
    PS> .\scripts\build_windows.ps1
#>

[CmdletBinding()]
param(
    [switch]$SkipInstall,
    [string]$FlutterHome = "$env:USERPROFILE\flutter"
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($id)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Step($msg) {
    Write-Host ""
    Write-Host "==> $msg" -ForegroundColor Cyan
}

function WaitForWinget {
    # winget install неблокирующий для .exe bundles — добавим -h ожидание завершения.
    # Все install-вызовы ниже используют --wait.
}

$repo = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $repo

Write-Host "Negern VPN — Windows build bootstrap" -ForegroundColor Green
Write-Host "Repo: $repo"
Write-Host "Flutter SDK: $FlutterHome"

# ------------------------------------------------------------------
# 1. Проверка админских прав (для установки VS Build Tools)
# ------------------------------------------------------------------
if (-not $SkipInstall -and -not (Test-Admin)) {
    Write-Warning "Нужны права администратора для установки Visual Studio Build Tools."
    Write-Host "Перезапускаю скрипт через UAC..."
    $argsStr = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    Start-Process powershell -Verb RunAs -ArgumentList $argsStr
    exit
}

# ------------------------------------------------------------------
# 2. winget
# ------------------------------------------------------------------
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw "winget не найден. Обновите Windows App Installer из Microsoft Store."
}

# ------------------------------------------------------------------
# 3. Git
# ------------------------------------------------------------------
if (-not $SkipInstall) {
    Step "Установка Git"
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        winget install --id Git.Git -e --silent --accept-source-agreements --accept-package-agreements
        # Обновим PATH в текущей сессии.
        $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
                    [Environment]::GetEnvironmentVariable('Path','User')
    } else {
        Write-Host "Git уже установлен: $((git --version))"
    }
}

# ------------------------------------------------------------------
# 4. Visual Studio 2022 Build Tools c C++ workload
# ------------------------------------------------------------------
if (-not $SkipInstall) {
    Step "Установка Visual Studio 2022 Build Tools + C++ workload (~8 GB, долго)"
    # Определяем, есть ли уже установка VS с C++ workload.
    $vswhere = "$env:ProgramFiles (x86)\Microsoft Visual Studio\Installer\vswhere.exe"
    $hasVc = $false
    if (Test-Path $vswhere) {
        $installs = & $vswhere -products * -requires Microsoft.VisualStudio.Workload.VCTools Microsoft.VisualStudio.Workload.NativeDesktop -format value -property installationPath
        if ($installs) { $hasVc = $true }
    }
    if (-not $hasVc) {
        winget install --id Microsoft.VisualStudio.2022.BuildTools -e --silent `
            --accept-source-agreements --accept-package-agreements `
            --override "--passive --wait --norestart --add Microsoft.VisualStudio.Workload.VCTools --add Microsoft.VisualStudio.Component.Windows11SDK.22621 --includeRecommended"
    } else {
        Write-Host "VS C++ Build Tools уже установлены."
    }
}

# ------------------------------------------------------------------
# 5. Flutter SDK (git clone, stable)
# ------------------------------------------------------------------
Step "Flutter SDK в $FlutterHome"
if (-not (Test-Path (Join-Path $FlutterHome 'bin\flutter.bat'))) {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw "git ещё не в PATH. Перезапустите скрипт или откройте новый PowerShell."
    }
    git clone --depth 1 -b stable https://github.com/flutter/flutter.git $FlutterHome
} else {
    Write-Host "Flutter уже установлен."
}

$flutterBin = Join-Path $FlutterHome 'bin'
if ($env:Path -notlike "*$flutterBin*") {
    $env:Path = "$flutterBin;$env:Path"
    # Добавим в User PATH навсегда.
    $userPath = [Environment]::GetEnvironmentVariable('Path','User')
    if ($userPath -notlike "*$flutterBin*") {
        [Environment]::SetEnvironmentVariable('Path',"$flutterBin;$userPath",'User')
    }
}

# ------------------------------------------------------------------
# 6. flutter config
# ------------------------------------------------------------------
Step "flutter --disable-analytics + enable-windows-desktop"
& "$flutterBin\flutter.bat" --disable-analytics
& "$flutterBin\flutter.bat" config --enable-windows-desktop --no-analytics | Out-Host

# ------------------------------------------------------------------
# 7. flutter doctor (информационно)
# ------------------------------------------------------------------
Step "flutter doctor"
& "$flutterBin\flutter.bat" doctor -v

# ------------------------------------------------------------------
# 8. Scaffold windows/ + pub get
# ------------------------------------------------------------------
Step "flutter create + pub get"
Push-Location "$repo\app"
try {
    & "$flutterBin\flutter.bat" create --platforms=windows --project-name negern --org com.negern --description "Negern VPN" . | Out-Host
    & "$flutterBin\flutter.bat" pub get | Out-Host

    Step "flutter build windows --release"
    & "$flutterBin\flutter.bat" build windows --release | Out-Host

    $releaseDir = "build\windows\x64\runner\Release"
    if (-not (Test-Path $releaseDir)) {
        # Fallback: старое именование (Flutter <3.19).
        $releaseDir = "build\windows\runner\Release"
    }
    if (-not (Test-Path "$releaseDir\negern.exe")) {
        throw "negern.exe не найден в $releaseDir"
    }

    $outDir = Join-Path $repo 'out\windows'
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    Copy-Item "$releaseDir\*" $outDir -Recurse -Force

    $exe = Join-Path $outDir 'negern.exe'
    $size = (Get-Item $exe).Length / 1MB
    Write-Host ""
    Write-Host ("==> ГОТОВО: {0} ({1:N2} MB)" -f $exe, $size) -ForegroundColor Green
    Write-Host "Весь Release-комплект (EXE + .dll + data\) лежит в: $outDir"
    Write-Host "Запуск: `"$exe`""
} finally {
    Pop-Location
}
