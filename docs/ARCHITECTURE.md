# Архитектура Negern VPN

## Слои

1. **UI (Flutter / Dart)** — виджеты, Riverpod-провайдеры, `go_router`.
2. **Core (Dart)** — модели, парсеры (`core/parsing`), sqflite-хранилище
   (`core/storage/database.dart`), сервис подписок (`core/services`),
   абстракция `VpnEngine`.
3. **Platform bridge (Dart)** — `VpnHost` интерфейс; реализации
   `PlatformVpnHost` (MethodChannel/EventChannel) и `MockVpnHost` (in-process,
   используется, если нативный плагин недоступен).
4. **Нативный host** — Kotlin `NegernVpnService` + `MainActivity`
   (Android), C++ плагин `negern_vpn_plugin` (Windows). Заготовки лежат
   в `app/native_stubs/` и копируются в сгенерированные `android/`, `windows/`.
5. **Go cores** (следующая итерация) — `native/xray-bridge`,
   `native/awg-bridge`, собираются в `.aar` / `.dll`.

## Дополнительные возможности клиента

- **Client preset (подмена клиента)** — `core/models/client_preset.dart`.
  Задаёт fingerprint (Reality), User-Agent (подписки) и spiderX. Пресеты:
  Happ / NekoBox / v2rayN / Xray-core / Hiddify / Negern.
- **Режим подключения** — `ConnectionMode` {tun, proxy}. В `proxy` xray-inbound
  переключается на локальный `socks` на 127.0.0.1:10808.
- **Авто-проверка серверов** — `AutotestService`: TCP-ping адреса/порта каждого
  профиля с интервалом 30–120 мин (настраивается в Settings). Результат пишется
  в `profiles.latency_ms` и подсвечивается в UI (зел./жёлт./красн.).
- **Speedtest** — `NetworkService.speedTest` (Cloudflare __down). Кнопка у
  каждого профиля.
- **Публичный IP** — `NetworkService.publicIp` (ipify.org). Плашка в AppBar
  с кнопкой скрытия (маскирует октеты).
- **Экспорт** — `ExportService.toVlessLinks` / `toAwgConfs`. В UI: QR + копия
  отдельного ключа, а также массовый экспорт всей подписки.
- **LAN-раздача через SOCKS5** — `LanProxyService` (чистый `dart:io`, RFC 1928,
  опционально RFC 1929 user/pass). Запускается на 0.0.0.0:1080. Это
  единственный способ, не использующий системные утилиты хотспота: создание
  Wi-Fi SoftAP требует кооперации драйвера Wi-Fi и доступно только через
  системные API ОС (Windows `NetworkOperatorTetheringManager`, Android
  `WifiManager.startLocalOnlyHotspot`).
- **Кастомный фон** — `wallpaperPathProvider`; путь сохраняется в `settings`,
  файл рисуется под Scaffold с полупрозрачной подложкой.

## Правило единственного активного соединения

Даже если UI разделён на две вкладки, ОС позволяет иметь только один TUN-интерфейс. Поэтому:

- `VpnSessionManager` (Dart) хранит `activeEngine` и гарантирует, что перед `start(engineB)` будет выполнен `stop(engineA)`.
- На нативном слое выполняется дополнительная защита: `VpnService.onStartCommand` проверяет, что предыдущий раннер завершён (`join` go-routine / WaitGroup).

## Каналы связи

- `negern/vpn` (MethodChannel):
  - `prepare()` → bool (Android only — запрос VPN-разрешения)
  - `start({engine, configJson, routing})` → void
  - `stop()` → void
  - `status()` → `{state, engine, uploadBytes, downloadBytes}`
- `negern/vpn/events` (EventChannel): поток `VpnStatusEvent` (подключается, статистика, ошибки).

## Xray data-path

```
App traffic → TUN → tun2socks (Go) → SOCKS in-memory → xray-core inbound
→ xray outbound (VLESS/XTLS/Reality) → сервер
```

Используем `sing-tun` (или `hev-socks5-tunnel`) внутри одного Go-бинарника с xray. Никаких внешних процессов.

## AmneziaWG data-path

```
App traffic → TUN → amneziawg-go (userspace) → UDP с обфускацией → сервер
```

`amneziawg-go` сам читает/пишет в TUN и ничего лишнего не нужно.

## Android specifics

- Один `VpnService` на всё приложение. Класс `NegernVpnService`.
- `VpnService.Builder` конфигурируется в зависимости от движка:
  - для AWG — адреса/DNS берутся из `[Interface]`.
  - для Xray — адрес виртуальный (напр., `10.200.0.2/32`) + DNS через fakeDNS или перехват :53.
- `protect(socket)` применяется к UDP/TCP сокетам Go, чтобы они шли не через TUN.

## Windows specifics

- `wintun.dll` — адаптер; требуется подпись драйвера в релизе.
- Плагин Flutter Windows загружает `xray.dll`/`awg.dll` через `LoadLibraryW` и дёргает C-функции.
- Elevation: для установки маршрутов и драйвера нужны права администратора. В проде — отдельный Windows Service с IPC (named pipe) к UI-процессу.

## Модели данных

См. `app/lib/core/models/*.dart` и `app/lib/core/storage/database.dart`.

## Парсинг конфигов

- `vless://uuid@host:port?security=reality&pbk=...&sid=...&sni=...&fp=chrome&type=tcp&flow=xtls-rprx-vision#name`
- AWG `.conf`:

```
[Interface]
PrivateKey = ...
Address = 10.0.0.2/32
DNS = 1.1.1.1
Jc = 4
Jmin = 40
Jmax = 70
S1 = 50
S2 = 100
H1 = 1
H2 = 2
H3 = 3
H4 = 4

[Peer]
PublicKey = ...
PresharedKey = ...
Endpoint = vpn.example.com:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
```
