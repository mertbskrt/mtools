# MTools

MTools is a mobile control panel that lets you manage your home/homelab
servers (Proxmox, AdGuard Home, NUT/UPS) from a single Flutter app. Built
for hobbyists and homelab enthusiasts who manage devices on their own
network.

> This is a personal homelab tool; it has not been tested for
> enterprise/production use.

This repository contains source code only. For pre-built, signed APK
releases, see: [mertbskrt/mtools-releases](https://github.com/mertbskrt/mtools-releases).

## Features

- **Proxmox VE management** — node/VM/container status, start/stop/restart,
  creating new VMs/containers, disk/CPU/RAM/temperature monitoring.
- **AdGuard Home control** — toggle protection, filter list management,
  query statistics.
- **UPS monitoring (NUT)** — status of connected UPS devices, battery/load
  info.
- **SSH Terminal** — direct terminal access to your saved servers.
- **Wake on LAN** — remotely wake devices on your network.
- **Background monitoring and notifications** — push notifications based
  on thresholds you set (CPU/RAM/disk/UPS, etc.), with an in-app
  notification history.
- **App lock** — PIN and/or biometric lock.
- **Cloud sync (optional)** — sign in with your Google account to sync
  server lists/settings across devices (via Firebase Firestore — requires
  connecting your own Firebase project, see below).

## Screenshots

| Home | Proxmox | Terminal |
|---|---|---|
| _placeholder_ | _placeholder_ | _placeholder_ |

_(Screenshots coming soon.)_

## Installation

### Requirements

- Flutter **3.41.9** or later (stable channel)
- Android Studio / Xcode (depending on platform)
- A Firebase project (for cloud sync and Google sign-in — without this
  step the app can still run the Proxmox/AdGuard/UPS/Terminal/WOL
  features locally, but the sign-in screen and cloud sync won't work)

```bash
git clone <this-repo>
cd mtools_v2
flutter pub get
```

### Connecting Your Own Firebase Project

This repository does not include `google-services.json`,
`firebase_options.dart`, or `firebase.json` (excluded via `.gitignore`) —
these are specific to each developer's own Firebase project. For an
example of what `firebase.json` looks like, see `firebase.json.example`;
the real file is generated automatically after the steps below.

1. Create a new project in the
   [Firebase Console](https://console.firebase.google.com).
2. Add an **Android app** to the project — use the `applicationId` value
   from `android/app/build.gradle.kts` as the package name.
3. Place the downloaded `google-services.json` file in `android/app/`.
4. Install the [FlutterFire CLI](https://firebase.google.com/docs/flutter/setup)
   and run it from the project root:
   ```bash
   dart pub global activate flutterfire_cli
   flutterfire configure
   ```
   This command automatically generates `lib/firebase_options.dart` for
   your project.
5. Enable the **Authentication → Google** provider in the Firebase
   Console.
6. Create Firestore and review the security rules (this app reads/writes
   per-user settings/server-list sync under `users/{uid}` — it's
   recommended you restrict the rules accordingly).

### Running

```bash
flutter run
```

## Network / Security Note

MTools connects to the servers you manage (Proxmox API, AdGuard Home API,
SSH, NUT) **directly over your local network** — this traffic never
passes through any server of the app's own. For Proxmox/AdGuard
connections, using a valid TLS certificate on your own servers is
recommended; SSH connections are encrypted with the standard SSH
protocol. For details on how credentials are stored and how to report a
security issue, see [SECURITY.md](SECURITY.md).

## Roadmap

- **`flutter_secure_storage` migration** — credentials currently live in
  standard SharedPreferences (app-private, plaintext); moving them to a
  store backed by the OS's hardware-backed encryption is planned.
- **Client-side encrypted cloud sync** — credentials currently aren't
  synced to the cloud at all (only server structure is); in the future,
  syncing credentials too — encrypted client-side so they're never
  visible in plaintext on the server — may be considered.

## License

MIT — see [LICENSE](LICENSE).
