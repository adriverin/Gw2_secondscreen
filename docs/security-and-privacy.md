# Security and privacy

- The ArenaNet key is sent only to `https://api.guildwars2.com` and stored with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`—available only while the device is unlocked and excluded from device migration/backup.
- Bridge pairing is a random 256-bit bearer token. Windows protects it for the current user with DPAPI. The stable bridge ID is a random GUID, not a hardware serial number.
- The API key is never sent to the bridge. Pairing tokens are never included in routine logs, UI diagnostics, or exported reports.
- Local telemetry uses authenticated, unencrypted LAN HTTP/WebSocket traffic. ATS permits local networking only, not arbitrary HTTP internet traffic.
- There is no cloud storage, analytics, advertising, GPS permission, packet interception, or game automation.
- Diagnostics are redacted by default: no account/character display names, credentials, portraits, inventory contents, or precise physical-device location.

The console must show a pairing token to bootstrap a local device; treat the QR as a credential. Press R to invalidate it. Production logging records connection/state changes and numeric map IDs, but not request headers, URLs containing tokens, full API payloads, or continuous telemetry.
