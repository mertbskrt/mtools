# Changelog

All notable changes to MTools are documented in this file.

## [3.2.1] — 2026-08-12

### New: Wake-on-LAN widget

- Added a home-screen widget for Wake-on-LAN — see your saved devices
  and wake any of them (or all at once) with a single tap, without
  opening the app.
- The widget supports the same small/medium/large sizes as the other
  three widgets, and can be configured (long-press → Configure) to
  show only specific devices.

### New: choose which servers appear in the Proxmox widget

- The Proxmox/system home-screen widget can now be configured (when
  you add it, or later via long-press → Configure) to show only
  specific servers instead of all of them. You can add the widget
  multiple times with a different server selection in each.

### Reliability

- MTools now tells the difference between "your phone has no internet"
  and "a specific server is unreachable." Previously, losing your
  phone's own WiFi/mobile signal could trigger three separate
  "unreachable" notifications (one each for Proxmox, UPS, and AdGuard)
  for what was really a single, unrelated problem. Now you get one
  clear notification when your connection drops and one when it's
  back, and the three widgets show "your device has no internet"
  instead of guessing at the server's status.
- The Proxmox and UPS home-screen widgets now tell "never set up" and
  "set up but currently unreachable" apart, matching how the AdGuard
  widget already worked — so an empty widget doesn't look like a
  configuration you forgot to finish.

### Design

- Brought the Proxmox, UPS, AdGuard, and Wake-on-LAN widgets into
  closer visual alignment: matching size breakpoints, touch target
  sizes on the Wake-on-LAN buttons, and consistent colors/typography
  across all four.
- Fixed the Wake-on-LAN widget's "wake all" button so tapping it
  repeatedly in quick succession doesn't resend packets to devices
  that were just woken.

## [3.2.0] — 2026-08-08

### Reliability

- UPS: when the NUT server becomes completely unreachable (as opposed to
  reachable but reporting the UPS itself as powered off), MTools now
  detects this, sends a dedicated "UPS Unreachable" notification, and
  marks the home-screen widget and in-app card as stale instead of
  silently freezing on the last known reading.
- Proxmox: the home-screen widget no longer freezes on stale data when
  a Proxmox server becomes completely unreachable — affected nodes are
  now marked offline in the widget, matching the existing in-app and
  notification behavior.
- AdGuard Home: added the same unreachable-detection UPS and Proxmox
  already had — a new "AdGuard Unreachable" notification, a stale-data
  indicator on the AdGuard screen, and a correct "no connection" state
  on the home-screen widget. Previously, a fully unreachable AdGuard
  server was invisible everywhere (no notification, frozen widget,
  frozen screen).

### New: Updates screen

- "Updates" in Settings now opens its own dedicated screen instead of
  checking inline. It shows your current version, the last time you
  checked, and — when an update is available — the release notes, file
  size, and an "Update Now" button in one place.

### Design

- About screen redesigned: removed the redundant "Up to date" status
  badge (this is now the Updates screen's job), reordered sections
  (developer info now appears before release notes), added a GitHub
  link to the footer, and fixed section dividers being nearly invisible
  in light themes.
- Fixed a contrast issue where the UPS stale-data warning color was
  hard to read against light theme backgrounds.

### Fixed

- Wake-on-LAN's on-screen confirmation after sending a UDP magic packet
  now says the packet was sent, rather than wording that could be read
  as confirming the device woke up (UDP has no delivery confirmation,
  unlike the SSH/API relay methods).
- Terminal SSH connections now explicitly request a 15-second
  keep-alive, helping the app notice a silently dropped network
  connection sooner.

### Other

- Various small consistency fixes found during a broader review:
  notification history icon/color matching for the new "unreachable"
  notification types, a missing category icon in notification
  settings, and design-token cleanup (border radius, hairline colors)
  in a couple of screens.

## [3.1.0] — 2026-07-10

### Design

- Refreshed visual identity across the entire app, including a new logo
  (the "sparkline-M" mark) used consistently in notifications, the app
  icon, and the launch screen.
- Tab switching is now instant (no animation), closer to native
  platform behavior — previous state (scroll position, expanded
  sections) is preserved when switching back.
- Rebuilt the native launch (splash) screen: it now follows the
  system's light/dark setting and shows the current logo, including
  proper support for Android 12+'s SplashScreen API.
- Refreshed the onboarding screens.
- Simplified the About screen (removed a redundant "Core Capabilities"
  section, rewrote the platform description, fixed a duplicated
  "Developer" heading, replaced the initials avatar with the app mark).
- The update-check flow now uses a small inline spinner and calmer,
  neutral result messaging instead of a success/celebration tone.
- Moved the notification history (bell) icon to the leading position
  of the app bar.

### Security

- **Server credentials (SSH passwords, Proxmox API tokens, AdGuard/NUT
  usernames and passwords) are no longer synced to the cloud at all.**
  Only non-sensitive server structure (name, host, port) is synced
  across devices; credentials stay device-local. Existing cloud
  accounts that still carry plaintext credentials from before this
  release are cleaned up automatically, once, the next time you sign
  in.
- Fixed a bug in the in-session "link Google account" flow (Settings →
  guest → sign in) that could push raw, unsanitized local data to the
  cloud and overwrite what was already there — it now goes through the
  same safe merge and cleanup path used at app startup.
- Release builds are now compiled with code shrinking/minification
  enabled, with the necessary keep rules for Firebase, Google Sign-In,
  and the notification/background-service plugins.
- Clarified cleartext network traffic handling for connecting to
  local/self-hosted servers (Proxmox, AdGuard Home, NUT) over your own
  LAN.

### Notifications

- The persistent "running in background" notification is now a single,
  quiet line, and the background monitoring service itself only runs
  when at least one notification rule is actually enabled — otherwise
  it stops itself and the notification disappears.
- Fixed the background service's persistent notification showing a
  stale/incorrect icon left over from an older version of the logo;
  all notification types now use the same current mark and a single
  consistent accent color.
- Rewrite of all notification copy: removed emoji and internal
  technical identifiers (usernames, API token names) from titles and
  bodies, and standardized on a single "target · detail · time" format
  across server, container/VM, resource-threshold, UPS, and terminal
  notifications.
- Notification history now renders older (pre-3.1.0) emoji-prefixed
  entries cleanly at display time, without needing to migrate stored
  data.

### Other

- Various stability and consistency fixes uncovered during a full
  pre-release review (static analysis cleanup, dead code removal,
  resource lifecycle fixes such as undisposed timers/controllers, and
  consistent use of the app's design tokens for color/spacing/motion).

## [3.0.2]

### Fixed

- Redesigned the theme system: the previous purple/blue gradient themes
  were replaced with a more restrained palette — OLED (true black),
  Coffee (warm dark tones), and Slate (neutral dark gray) in dark mode,
  each with a matching light-mode counterpart.
- Fixed the notification center showing a blurry, unrecognizable app
  icon (e.g. resembling a leaf) instead of the MTools mark.
- Fixed a false "Server Unreachable" notification triggered by brief
  network interface changes (e.g. switching from Wi-Fi to mobile
  data) — a notification is now only sent for a real, sustained
  outage.
- Fixed multiple configured servers being incorrectly marked offline
  when only one of them was actually unreachable.
- Fixed the AdGuard home-screen widget not updating while the app was
  closed.
- Fixed the persistent "running in background" notification sometimes
  failing to clear on its own, requiring manual dismissal.

## Earlier versions

Detailed release notes prior to 3.0.2 were not tracked in this
changelog.
