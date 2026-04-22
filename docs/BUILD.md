# Сборка Negern VPN

## Вариант A (самый быстрый): APK через Docker

Поставьте Docker Desktop (https://www.docker.com/products/docker-desktop/).
Убедитесь, что он запущен. Потом в корне репозитория:

```powershell
.\scripts\build_apk.ps1
```

Итог: `out/negern-release.apk` (подписан debug-ключом Flutter, устанавливается
на любое Android 5.0+ устройство). Первая сборка тянет ~3–4 GB образа и
занимает 10–20 минут; последующие — минуты.

Установка на телефон:

```powershell
adb install -r out\negern-release.apk
```

Либо скопируйте файл на устройство и откройте его (потребуется разрешение на
установку из неизвестных источников).

## Вариант B: локальная разработка (UI-скелет + моки)

```powershell
cd app
flutter create --platforms=android,windows --project-name negern .  # один раз
# Скопируйте заготовки из app/native_stubs (см. native_stubs/README.md)
flutter pub get
flutter analyze
flutter test
flutter run -d windows
# или
flutter run -d <androidDeviceId>
```

Если нативные заготовки ещё не скопированы — приложение автоматически падает
на `MockVpnHost` в Dart и работает без нативной части (эмулирует
connected/disconnected для обеих вкладок).

## Следующая итерация — Go-мосты

### xray-bridge (VLESS + sing-tun)

```powershell
cd native/xray-bridge
# Android AAR
gomobile bind -target=android -androidapi=21 -o ../../app/android/app/libs/xray.aar .
# Windows DLL + C header
go build -buildmode=c-shared -o ../../app/windows/libs/xray.dll .
```

### awg-bridge (amneziawg-go)

```powershell
cd native/awg-bridge
gomobile bind -target=android -androidapi=21 -o ../../app/android/app/libs/awg.aar .
go build -buildmode=c-shared -o ../../app/windows/libs/awg.dll .
```

### Android

1. В `app/android/app/build.gradle` подключите `libs/*.aar`:

```gradle
android {
    ...
    defaultConfig { ndk { abiFilters "armeabi-v7a", "arm64-v8a", "x86_64" } }
}
dependencies {
    implementation(fileTree(dir: 'libs', include: ['*.aar']))
}
```

2. `NegernVpnService.kt` использует `VpnService.Builder` → `ParcelFileDescriptor`;
   `detachFd()` передаётся в Go-функции `StartVless(configJson, tunFd)` /
   `StartAwg(configIni, tunFd)`. `protect(socket)` применяется ко всем
   upstream-сокетам (см. callback из Go).

### Windows

1. Положите `xray.dll` / `awg.dll` и `wintun.dll` рядом с exe.
2. Флаги `LoadLibraryW` + `GetProcAddress`. Адаптер создаётся из Go через
   `golang.zx2c4.com/wintun` (для AWG) или явно (для Xray TUN).
3. Маршруты — `CreateIpForwardEntry2` / `netsh interface ip set route`.
4. Для релиза оформить отдельный Windows Service (запуск от SYSTEM),
   UI-процесс общается с ним по named pipe (см. `docs/ARCHITECTURE.md`).

## Подпись

- **Android**: Play-ready keystore, подпись AAB.
- **Windows**: EV Code Signing + подпись `wintun.dll` драйвера WHQL.
