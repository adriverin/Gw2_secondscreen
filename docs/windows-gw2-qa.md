# Windows and real Guild Wars 2 QA

Use a Windows 10/11 PC on a Private network. Run the bridge and GW2 as the same user and elevation. `--validate-mumble` prints one readable snapshot per second.

| Step | Action | Expected bridge and iOS state |
|---|---|---|
| 1 | Launch bridge before GW2 | Bridge says waiting; iOS says connected to PC, GW2 not running. |
| 2 | Launch GW2 and enter a character | Connected, character and map appear. |
| 3 | Walk and turn | Position and heading move smoothly without implausible jumps. |
| 4 | Mount/dismount | `mountIndex` changes in validation output. |
| 5 | Enter/leave combat | `uiState`/combat changes. |
| 6 | Waypoint teleport | Old marker becomes stale/hidden during transition; new map/objective layer wins. |
| 7 | Portal to another map | Same as teleport; route does not complete from stale data. |
| 8 | Queensdale → Divinity's Reach → third map | Map ID, marker, and objectives match every transition. |
| 9 | Character select | Missing identity is tolerated without repeated banners. |
| 10 | Log in another character | Current character rematches and the old identity does not persist. |
| 11 | Close/reopen GW2 | Connected-no-GW2 then live, without restarting the app. |
| 12 | Close/restart bridge | Reconnecting then live; stable token/bridge identity avoids re-pairing. |
| 13 | Run bridge with `--reset-pairing` | iOS reports Pair Again; new QR restores service. |
| 14 | Sleep/wake PC | Reconnect resumes when the PC/network returns. |
| 15 | Change the PC network/DHCP address | iOS explains that the PC cannot be reached; scan the new QR. |
| 16 | Firewall Private access denied/allowed | Failure is reproducible; Private access fixes it. Public access is not requested. |

Run `GW2Bridge.exe --validate-mumble` and verify `uiVersion`, `uiTick`, identity, profession, map ID, player X/Y, avatar vectors, camera front, UI state, and mount once per second. Impossible/non-finite layouts must say invalid rather than emit telemetry.
