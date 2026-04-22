# Negern VPN

Кроссплатформенный VPN-клиент для Android и Windows.

- **UI**: Flutter (Dart), Riverpod, Drift.
- **Ядра**: Xray-core (VLESS/XTLS/Reality) и AmneziaWG 1.5 — оба собираются из Go.
- **Принцип**: две независимые вкладки (VLESS / Amnezia WG), но одно активное VPN-соединение.

## Структура репозитория

```
negern/
├── app/                       # Flutter-приложение (UI + бизнес-логика)
├── native/
│   ├── xray-bridge/           # Go-обёртка над xray-core + tun2socks
│   └── awg-bridge/            # Go-обёртка над amneziawg-go
└── docs/
    └── ARCHITECTURE.md
```

См. `docs/ARCHITECTURE.md` для архитектурных деталей.

## Быстрый старт (dev)

```powershell
# 1. Flutter
cd app
flutter pub get
flutter run -d windows        # или -d <deviceId> для Android

# 2. Go-мосты (когда будут готовы исходники)
cd ../native/xray-bridge
gomobile bind -target=android -androidapi=21 -o ../../app/android/app/libs/xray.aar .
go build -buildmode=c-shared -o ../../app/windows/libs/xray.dll .
```
