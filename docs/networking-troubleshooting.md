# Networking and troubleshooting

The bridge listens on TCP `38291` by default on all PC interfaces. Pairing uses an authenticated HTTP validation request followed by `ws://` on the same LAN endpoint. iOS ATS is limited to `NSAllowsLocalNetworking`; arbitrary internet HTTP loads are not allowed. ArenaNet API, render service, and tile traffic remain HTTPS.

Allow **GW2 Companion Bridge on Private networks** in Windows Firewall. The bridge never silently changes firewall configuration and users should not expose it on Public networks. Both devices must be on the same non-isolated Wi-Fi/LAN; guest networks and client isolation can block peer traffic.

“PC unreachable” means the app could not contact the bridge. “Connected to PC; GW2 not running” means networking and authentication succeeded but MumbleLink has no fresh in-world telemetry. “Pair Again” means the token changed. “Update Required” means protocol/identity negotiation failed. After a DHCP address change, scan the bridge’s current QR code; automatic discovery is intentionally deferred.

The WebSocket is authenticated but not encrypted. Use a trusted home network. The bearer token is random, stored in iOS Keychain and Windows DPAPI, and excluded from logs and diagnostics.
