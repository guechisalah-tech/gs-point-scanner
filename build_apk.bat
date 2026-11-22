@echo off
REM يتطلب Flutter SDK + Android SDK. شغّل الملف بالنقر المزدوج من داخل مجلد المشروع.
if not exist android call flutter create --platforms=android --org dz.gs --project-name gs_point_scanner .
copy /Y android_overrides\AndroidManifest.xml android\app\src\main\AndroidManifest.xml
call flutter pub get
call flutter build apk --release
echo APK: build\app\outputs\flutter-apk\app-release.apk
pause
