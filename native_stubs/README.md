# Нативные заготовки

Эти файлы — шаблоны, которые нужно скопировать в сгенерированные Flutter-ом
папки `android/` и `windows/` **после** выполнения в корне `app/`:

```powershell
flutter create --platforms=android,windows --project-name negern .
```

## Android

1. Скопируйте `android/NegernVpnService.kt` и `android/MainActivity.kt` в
   `app/android/app/src/main/kotlin/com/example/negern/`.
2. В `AndroidManifest.xml` внутри `<application>` добавьте:

```xml
<service
    android:name=".NegernVpnService"
    android:permission="android.permission.BIND_VPN_SERVICE"
    android:exported="false">
    <intent-filter>
        <action android:name="android.net.VpnService" />
    </intent-filter>
</service>
```

3. Добавьте разрешения:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

## Windows

1. Скопируйте `windows/negern_vpn_plugin.cpp`/`.h` в
   `app/windows/runner/` (или оформите как отдельный Flutter-plugin проект).
2. В `runner/CMakeLists.txt` добавьте `.cpp` в `add_executable(...)`.
3. В `runner/flutter_window.cpp` зарегистрируйте плагин вызовом
   `NegernVpnPlugin::RegisterWithRegistrar(registrar)` после создания
   FlutterViewController.

Оба нативных хоста сейчас — **заглушки**: они отвечают на MethodChannel
`negern/vpn` и эмулируют статус `connected` через EventChannel
`negern/vpn/events`. Реальные ядра (Xray / amneziawg-go) подключаются
в следующей итерации.
