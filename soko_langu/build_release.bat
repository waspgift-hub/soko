@echo off
echo Building Soko Vibe Release APK with obfuscation...
cd /d "%~dp0"
flutter build apk --release --obfuscate --split-debug-info=build/app/outputs/symbols
if %errorlevel% equ 0 (
    echo.
    echo APK ready: build\app\outputs\flutter-apk\app-release.apk
) else (
    echo Build failed.
)
pause
