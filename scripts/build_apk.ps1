#Requires -Version 5.1
<#
.SYNOPSIS
    Собирает Negern VPN APK в Docker и кладёт его в ./out/negern-release.apk.

.DESCRIPTION
    Требования: установленный Docker Desktop (docker.exe в PATH).
    Первая сборка тянет ~3–4 GB образа ghcr.io/cirruslabs/flutter:stable
    и билдит APK (всего ~10–20 минут). Последующие — минуты за счёт кеша.

.EXAMPLE
    PS> .\scripts\build_apk.ps1
#>

$ErrorActionPreference = 'Stop'

# Корень репозитория = родитель папки scripts.
$repo = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $repo

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Error "docker не найден в PATH. Установите Docker Desktop: https://www.docker.com/products/docker-desktop/"
    exit 1
}

$out = Join-Path $repo 'out'
New-Item -ItemType Directory -Force -Path $out | Out-Null

Write-Host "==> docker build (это может занять 10-20 минут при первом запуске)..." -ForegroundColor Cyan
docker build -t negern-apk -f Dockerfile .
if ($LASTEXITCODE -ne 0) { throw "docker build failed" }

Write-Host "==> экспорт APK в $out..." -ForegroundColor Cyan
docker run --rm -v "${out}:/out" negern-apk
if ($LASTEXITCODE -ne 0) { throw "docker run failed" }

$apk = Join-Path $out 'negern-release.apk'
if (Test-Path $apk) {
    $size = (Get-Item $apk).Length / 1MB
    Write-Host ("==> ГОТОВО: {0} ({1:N2} MB)" -f $apk, $size) -ForegroundColor Green
    Write-Host "Установка на Android: adb install -r `"$apk`" или скопируйте на устройство и откройте."
} else {
    Write-Error "APK не найден по пути $apk"
    exit 2
}
