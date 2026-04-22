# syntax=docker/dockerfile:1.6
#
# Сборка Negern VPN APK. Базовый образ cirruslabs уже содержит:
#   - Flutter SDK (stable)
#   - Android SDK + build-tools + platform-tools
#   - OpenJDK 17
#   - принятые лицензии
#
# Использование:
#   docker build -t negern-apk -f Dockerfile .
#   docker run --rm -v ${PWD}/out:/out negern-apk
#
# Итог: ./out/negern-release.apk
# (подписан debug-ключом Flutter — устанавливается на любое Android-устройство).

FROM ghcr.io/cirruslabs/flutter:stable AS build

ENV PUB_CACHE=/home/cirrus/.pub-cache
WORKDIR /project

# Копируем только app/ — остальное (docs/, scripts/) для сборки не нужно.
COPY app/ /project/

# flutter create достраивает недостающие платформенные папки (android/).
# Существующие файлы (pubspec.yaml, lib/, test/, assets/) не перезаписываются.
RUN flutter create \
      --platforms=android \
      --project-name negern \
      --org com.negern \
      --description "Negern VPN" \
      . \
 && rm -f test/widget_test.dart

# Копируем нативные заготовки Android в сгенерированный android/.
RUN mkdir -p android/app/src/main/kotlin/com/negern/negern \
 && cp -f native_stubs/android/MainActivity.kt \
          android/app/src/main/kotlin/com/negern/negern/MainActivity.kt \
 && cp -f native_stubs/android/NegernVpnService.kt \
          android/app/src/main/kotlin/com/negern/negern/NegernVpnService.kt \
 && sed -i 's|package com.example.negern|package com.negern.negern|g' \
          android/app/src/main/kotlin/com/negern/negern/*.kt

# Минимальные права + регистрация NegernVpnService в манифесте.
RUN python3 - <<'PY'
import re, pathlib
p = pathlib.Path('android/app/src/main/AndroidManifest.xml')
s = p.read_text()
perms = (
    '    <uses-permission android:name="android.permission.INTERNET"/>\n'
    '    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>\n'
    '    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>\n'
    '    <uses-permission android:name="android.permission.CAMERA"/>\n'
)
if 'android.permission.INTERNET' not in s:
    s = re.sub(r'(<manifest[^>]*>)', r'\1\n' + perms, s, count=1)
service_xml = (
    '        <service\n'
    '            android:name=".NegernVpnService"\n'
    '            android:permission="android.permission.BIND_VPN_SERVICE"\n'
    '            android:exported="false">\n'
    '            <intent-filter>\n'
    '                <action android:name="android.net.VpnService"/>\n'
    '            </intent-filter>\n'
    '        </service>\n'
)
if 'NegernVpnService' not in s:
    s = s.replace('</application>', service_xml + '    </application>')
p.write_text(s)
PY

RUN flutter --disable-analytics \
 && flutter pub get \
 && flutter build apk --release

# --- финальный слой с одним APK ---
FROM debian:bookworm-slim AS export
WORKDIR /out
COPY --from=build /project/build/app/outputs/flutter-apk/app-release.apk /opt/app-release.apk

CMD ["sh", "-c", "mkdir -p /out && cp /opt/app-release.apk /out/negern-release.apk && ls -la /out/"]
