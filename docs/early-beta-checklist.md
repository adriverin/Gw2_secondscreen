# Early Beta checklist

Use this on a **physical iPhone**, a **Windows PC**, a **real Guild Wars 2 client**, and a **real ArenaNet API key**. Simulator, mock telemetry, and fixture account data do not count as physical validation.

Severity when recording a failed QA check:

| Severity | Meaning |
|---|---|
| **P0** | Data loss, crash, wrong map, cannot connect, or security issue |
| **P1** | Major feature unusable |
| **P2** | Usability issue with a workaround |
| **P3** | Cosmetic or minor |

Do not mark Pass because data exists. Confirm the visual or behavioral check. Export **Settings → Developer → Real Hardware QA → Export Support Bundle** (Developer Mode: tap the version row seven times).

## Setup

- [ ] Install the signed iPhone app. Record app version/build, iOS version, and device model.
- [ ] Create an ArenaNet API key with `account`, `characters`, `inventories`, `builds`, `progression`, `unlocks`, and `wallet`. Do not paste it into chat, notes destined for export, or screenshots you will share.
- [ ] Run GW2 Companion Bridge on the Windows PC as the same user/elevation as Guild Wars 2. Allow it on **Private** networks in Windows Firewall.
- [ ] Pair by QR or manual LAN address. Confirm the iPhone reaches **LIVE** after entering a character.

## Core

- [ ] Live map: player marker moves with the character.
- [ ] Map alignment: stand on a Core Tyria waypoint, run **Real Hardware QA → Map Alignment**, record delta/distance, and confirm visual overlap. Repeat for a POI, a map edge, and an expansion map if official artwork exists.
- [ ] Map transition: Core map A → portal/waypoint → map B. Record map ID, name, tiles, POIs, player marker, gathering, target, and route.
- [ ] Character switch: Character A → character select → Character B. Confirm live identity, profile match, and no stale name.
- [ ] Inventory hub, Bank, Materials, Shared Inventory, and a character bag versus the real account. Confirm **LIVE ACCOUNT RESPONSE** vs **CACHED** labels.
- [ ] Today: Wizard's Vault, daily, weekly, claimed state, world bosses, daily crafting, raids, dungeons.

## Resilience

- [ ] Wi-Fi off/on on the iPhone; confirm automatic reconnect.
- [ ] Close and restart the bridge; confirm Reconnecting then LIVE. Record event-log timestamps.
- [ ] Close and relaunch Guild Wars 2; confirm **GW2 not running**, then LIVE.
- [ ] Background the app 30 seconds and return.
- [ ] Start a session, lock one task, skip one task, force quit, relaunch. Session, locked, and skipped should restore. Navigation should wait for fresh telemetry.

## Session

- [ ] Create a goal.
- [ ] Plan a session.
- [ ] Start the session.
- [ ] Navigate to a live target.
- [ ] Refresh progress without losing locked/skipped tasks.

## Report

Send back:

1. Support bundle text/JSON from QA Mode (redacted; no API key or pairing token).
2. Pass/Fail for each QA card, with P0–P3 on failures and a short note.
3. Map alignment PLAYER / WAYPOINT / DELTA / DISTANCE for at least one Core Tyria waypoint.
4. MumbleLink card values: status, uiTick, map ID, mount, combat, packets/sec, telemetry age (character name redacted).
5. Inventory counts (characters, bag slots, bank occupied, material entries, shared slots) plus whether Bank/Materials were LIVE or CACHED.
6. Event log around any reconnect failure.
7. Any crash, wrong-map, or security issue as **P0**.

Soak simulation in Developer Mode does **not** replace a 30-minute real play session on device.
