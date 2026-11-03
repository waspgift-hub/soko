# Soko Langu Offline USSD

This is the LAN-only USSD system requested for a PC + Android phone on the same Wi-Fi/router. It does **not** require internet, Firebase, ClickPesa, or a payment API.

## How it works

1. Run `SokoLangu-USSD.exe` on Windows.
2. The EXE prints one or more `PHONE:` URLs and a `TOKEN`.
3. Connect the Android phone to the **same router/Wi-Fi** as the PC. Internet is not required.
4. Open the Offline USSD APK and enter the PC URL and token.
5. Press CONNECT.
6. The APK sends `*123#` and menu selections to the PC over the local network.
7. The PC returns the USSD screen/menu immediately.

## Important

This is an **offline USSD simulator/session over LAN**. A normal Android app cannot make a carrier's native dialer execute a real telecom `*123#` session without the mobile operator/network USSD gateway. This implementation gives the requested PC-to-phone USSD experience without internet.

## Local development

```bash
cd offline_ussd
npm test
node server.js
```

## Artifacts

GitHub Actions builds:

- `SokoLangu-USSD-Windows` — portable Windows EXE
- `SokoLangu-Offline-USSD-APK` — Android release APK

The workflow also runs the protocol E2E tests before producing the artifacts.
