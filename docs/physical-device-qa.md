# Physical-device QA

No physical-device result should be recorded from Simulator evidence. Record device, OS, app build, bridge build, network, and date with each run.

## iPhone

- [ ] Confirm at least 8 GB free on the Mac before building.
- [ ] Delete the app, install a signed Debug build, and verify fresh onboarding.
- [ ] Skip both setup paths; confirm Map browsing remains usable.
- [ ] Reset, connect account only, and verify Today is the initial destination.
- [ ] Create a real key with only the documented permissions; verify checking, connected identity, and permission list.
- [ ] Test invalid/revoked key, limited key, offline, timeout, and cached-data messages.
- [ ] Lock/unlock and relaunch; verify the Keychain-backed account remains connected.
- [ ] Deny Camera; verify manual pairing remains available and no crash occurs.
- [ ] Grant Camera; scan valid, malformed, and unsupported-version QR codes.
- [ ] Verify the Local Network prompt uses the bundled explanation; deny it, retry, then enable it in Settings.
- [ ] Pair manually with private IPv4/hostname, valid port, and token; reject invalid fields locally.
- [ ] Verify live player position/heading, current character, map, objectives, gathering, target, and route.
- [ ] Background for 30 seconds; confirm no aggressive reconnection, then foreground and verify quick recovery.
- [ ] Force quit during Map, Today, Goal Detail, route navigation, and an active session; relaunch and verify persisted state.
- [ ] Turn Wi-Fi off/on and leave/return to Wi-Fi; confirm one connection recovers without restart.
- [ ] Close/restart bridge; confirm reconnect. Reset the bridge token; confirm Pair Again.
- [ ] Close/reopen GW2; confirm Connected to PC / GW2 not running, then live recovery.
- [ ] Rotate portrait/landscape with a target, route, sheet, and active session; confirm state is retained.
- [ ] Test Dynamic Type at Default, Large, and Accessibility XXL.
- [ ] Run VoiceOver through Onboarding, Map controls, Today, Goals, Session, Characters, Inventory, Account, and Settings.
- [ ] Load online data, terminate, disable internet, relaunch; confirm saved account/Today data and LAN telemetry remain useful.
- [ ] Run live Map for 30 minutes; record CPU, memory, energy, network traffic, and responsiveness using Instruments.

## iPad

- [ ] Repeat all applicable iPhone checks.
- [ ] Test 11-inch and 13-inch devices in portrait and landscape.
- [ ] Test full screen, narrow resizable window, and supported multitasking layouts.
- [ ] Verify sidebar selection, Map controls, Today cards, and Session layout do not clip or reset.

## Coordinate sampling

- [ ] Core Tyria waypoint and POI.
- [ ] Expansion-map waypoint and POI.
- [ ] Map edge.
- [ ] Elevated terrain.
- [ ] Underground-like area where the map projection is applicable.
- [ ] Export a redacted calibration report for every sample and record delta/distance; never introduce an undocumented offset.

Phase 6D adds **Settings → Developer → Real Hardware QA** (seven taps on the version row). Use `docs/early-beta-checklist.md` for the first physical beta pass and record P0–P3 severity on failures.
