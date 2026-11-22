#!/usr/bin/env bash
# يتطلب Flutter SDK + Android SDK. التشغيل: ./build_apk.sh
set -e
[ -d android ] || flutter create --platforms=android --org dz.gs --project-name gs_point_scanner .
cp android_overrides/AndroidManifest.xml android/app/src/main/AndroidManifest.xml
flutter pub get
flutter build apk --release
echo "APK: build/app/outputs/flutter-apk/app-release.apk"
