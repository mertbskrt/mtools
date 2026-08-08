# Security

MTools is a personal homelab tool. This document honestly describes
where your data is stored and what to do if you find a security issue.

## Where credentials are stored

Proxmox API tokens, SSH passwords, and AdGuard Home / NUT-UPS
usernames-passwords are stored **only on your device**, in standard
Android SharedPreferences — in plaintext, in app-private storage
(inaccessible to other apps). This data is **never synced to the
cloud**: when you sign in with Google, the only thing that syncs across
devices is the server's *structure* (name, host, port, URL) — password/
token fields are never written to Firestore.

`flutter_secure_storage` (a store backed by the OS's hardware-backed
encryption) isn't used yet — this is a known roadmap item (see README).

## Cloud sync

When you sign in with your Google account, only the following data is
written to your `users/{uid}` document in Firestore: server structure
(excluding credentials), theme preference, tab layout, node ordering,
notification rules, and the Wake-on-LAN device list. Firestore access is
**locked per uid** — each user can only read and write their own
document.

## Found a security issue?

Please email **mertbaskurt14@gmail.com** directly instead of opening a
GitHub issue. Include as much detail as you can (steps, affected
version) — I'll try to respond within a reasonable time.
