# GW2 Companion

GW2 Companion is an unofficial, local-first iPhone and iPad second screen for Guild Wars 2. Its home screen follows the character on a pan/zoom map, overlays official world objectives and gathering locations, and provides live Nearby, target direction/distance, local visit history and geometric route playback. A native Character & Account Hub uses the official Guild Wars 2 API to show the character roster, equipment and build templates, bag contents, wallet, account summary, and fast account-wide item search.

Live position does **not** come from the GW2 web API:

```text
Guild Wars 2 → MumbleLink → Windows bridge → authenticated LAN WebSocket → iPhone map
ArenaNet API ───────────────────────────────────────────────────────→ iPhone account views
```

The bridge never receives the ArenaNet API key. The iPhone stores API and bridge credentials in Keychain. There are no user accounts, analytics, cloud service, or location/GPS permission.

## Requirements

- Xcode 26 or newer and XcodeGen to build the iOS 17+ app
- An iPhone/iPad on the same LAN as the Windows PC (the simulator also supports in-app mock mode)
- Windows 10/11 (the packaged bridge is self-contained; the .NET SDK is needed only when building from source)
- Guild Wars 2 for real telemetry
- Optional ArenaNet API key with `account`, `characters`, `inventories`, `builds`, and `wallet` permissions

## Repository

```text
.
├── bridge/
│   ├── GW2Bridge/              # .NET bridge, MumbleLink reader and simulator
│   └── GW2Bridge.Tests/        # deterministic parser/protocol/staleness tests
├── data/gathering/             # original development-only marker sample
├── docs/                       # architecture, protocol, coordinates, development
├── ios/GW2Companion/
│   ├── Sources/                # SwiftUI app
│   ├── Tests/                  # decoding, coordinates, gathering and batching
│   ├── Resources/
│   ├── project.yml             # XcodeGen source
│   └── GW2Companion.xcodeproj/
└── protocol/
    ├── telemetry.schema.json
    └── examples/telemetry.v1.json
```

## Run the bridge

From the repository root on Windows:

```powershell
dotnet restore bridge/GW2Bridge/GW2Bridge.csproj
dotnet run --project bridge/GW2Bridge/GW2Bridge.csproj
```

Allow TCP port `38291` on the Windows private-network firewall when prompted. The console shows GW2/MumbleLink mode, the LAN address, a pairing JSON payload, and an ASCII QR code. Keep the window open while playing. Start the bridge before Guild Wars 2 (or restart the game once after starting the bridge) so the game can attach to the shared-memory mapping.

The bridge creates one pairing token and protects it with Windows Data Protection for the current Windows user. After upgrading from an older build, scan the QR code once; the iPhone then reconnects after normal bridge restarts. Use `--reset-pairing` only when you deliberately want to invalidate paired phones and create a new QR code.

If Guild Wars 2 is launched with a custom `-mumble NAME` option, give the bridge the same name:

```powershell
dotnet run --project bridge/GW2Bridge/GW2Bridge.csproj -- --mumble-name NAME
```

Remove `-mumble 0`, which disables MumbleLink. Run the bridge and the game as the same Windows user and at the same elevation level (normally, neither should be run as administrator).

Use another port with `--port 40000`.

## Map layers and gathering data

The iPhone downloads static objectives for the current map and floor from ArenaNet's `/v2/continents` API and caches map/language-specific snapshots on disk. The Layers panel controls waypoints, points of interest, vistas, renown hearts, hero challenges, mastery insights, adventures and gathering categories independently. Nearby and generated routes use only visible layers.

“Visited by Companion” means the live player entered a local arrival radius. “Marked complete” means the user explicitly set a local state. Neither claims that the Guild Wars 2 API reported per-character map completion. Route generation is a geometric nearest-neighbor suggested order and does not account for terrain, portals or elevation.

Landmark and gathering markers use the matching in-game artwork published through ArenaNet's `/v2/files` render-service catalog, with built-in symbols as an offline/error fallback.

Possible gathering locations come from a versioned conversion of the CC0 Tyrian Gathering Marker Project. The bundled snapshot contains 1,418 locations on maps 20, 21, 23, 27, 29, 34, 51, 54, 65, and 73. Resource nodes vary by day and map instance, so these markers describe places to check rather than live spawns. Walking near a marker gives it a yellow outline; tapping it separately marks it harvested. Attribution and snapshot details are in `ios/GW2Companion/Resources/THIRD_PARTY_NOTICES.md`.

## Simulation mode

The full PC-to-phone path can be tested without Windows or GW2:

```bash
dotnet run --project bridge/GW2Bridge/GW2Bridge.csproj -- --simulate
```

In the iOS app, open the computer button on Map and scan the console QR code. On the simulator, enter host `127.0.0.1`, port `38291`, and the token from the pairing JSON. The UI should become **LIVE**, show `Test Mesmer` on map 15, and move continuously through the sample gathering markers.

For an iOS-only demonstration, choose **Developer → Start simulated movement** in the same pairing screen. That exercises the identical store/map/gathering pipeline without a socket.

## Build and test iOS

```bash
cd ios/GW2Companion
xcodegen generate
xcodebuild -project GW2Companion.xcodeproj \
  -scheme GW2Companion \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/gw2companion-derived \
  CODE_SIGNING_ALLOWED=NO build

xcodebuild -project GW2Companion.xcodeproj \
  -scheme GW2Companion \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /tmp/gw2companion-tests \
  CODE_SIGNING_ALLOWED=NO test
```

For a physical phone, open `ios/GW2Companion/GW2Companion.xcodeproj`, select your development team and bundle identifier, select the phone, and Run. Accept the camera permission only if scanning QR, and accept local-network access. No physical-location permission is requested.

The command-line build above is an unsigned compile check. To run in Simulator with working Keychain pairing, use Xcode's Run action or repeat the build without `CODE_SIGNING_ALLOWED=NO` so Xcode applies simulator ad-hoc signing.

## Pair a phone

1. Start the bridge and Guild Wars 2 (or add `--simulate`).
2. Put the PC and phone on the same trusted LAN/Wi-Fi.
3. On Map, tap the computer button, then **Scan QR code**.
4. If scanning is unavailable, enter the displayed IP, port, and pairing token manually.
5. A bad or missing token shows **PAIR AGAIN**. Normal bridge restarts reuse the protected token; only `--reset-pairing` deliberately invalidates the saved pairing.

MVP LAN traffic is plain `ws://`, so use it only on a network you trust. The random token prevents unauthenticated subscriptions but does not encrypt character/location data; see [protocol security](docs/protocol.md#security).

## Connect a GW2 account

Open Account and paste a key created at [ArenaNet account applications](https://account.arena.net/applications). The app validates it with `/v2/tokeninfo`, saves it only after validation, and lists granted permissions without ever redisplaying the secret. Missing optional permissions disable only the affected data. Pull to refresh account screens.

The Characters tab shows a visual roster and marks the character reported by live MumbleLink telemetry. Character profiles provide Equipment, Build, and Inventory sections, including equipment/build-tab switching and reusable item, trait, and skill detail sheets. A locally chosen character portrait can be attached with PhotosPicker; it remains on device and can be removed at any time.

The Inventory tab searches a pre-aggregated local index spanning every character, bank, shared inventory, and material storage. Search does not issue per-keystroke API requests. Material storage is grouped with ArenaNet's material-category metadata. Previously loaded account and metadata caches remain visible with a saved/offline indicator when refresh fails.

On iPad, the four primary areas use a native sidebar and content column. On iPhone they use the same views in a tab bar rather than a separate implementation.

## Test the bridge

```bash
dotnet test bridge/GW2Bridge.Tests/GW2Bridge.Tests.csproj
dotnet publish bridge/GW2Bridge/GW2Bridge.csproj -c Release -r win-x64 \
  --self-contained true -p:PublishSingleFile=true
```

## Real GW2/MumbleLink validation

This environment was macOS and could not perform real MumbleLink validation. On Windows:

1. Launch Guild Wars 2 and enter the world on a non-competitive map.
2. Run the bridge without `--simulate`.
3. Pair the phone and confirm the character, map ID, and coordinates update while moving.
4. Stop GW2 and confirm **GW2 NOT RUNNING**; restart it and confirm recovery.
5. Stop the bridge and confirm **BRIDGE OFFLINE**/**RECONNECTING**, followed by automatic reconnection after restart without another QR scan.
6. Enter a competitive map and confirm the marker does not falsely move when continent position is unavailable.

## Limitations

- Real MumbleLink was implemented and parser-tested, but not executed against Guild Wars 2 in this macOS environment.
- The official tile artwork can be outdated or missing for newer maps. The app keeps overlays usable on a neutral background.
- Live position requires the Windows bridge; `/v2` has no live coordinates.
- Competitive maps can restrict useful continent-position telemetry.
- Normal mode bundles 1,418 possible locations from the versioned CC0 Tyrian Gathering Marker Project snapshot; synthetic samples are restricted to simulation mode. These are not confirmed active spawns.
- “Visited” means the player entered a radius, not that the node was harvested; session visits reset on app relaunch.
- MVP WebSocket transport is authenticated but not TLS-encrypted.
- Automatic discovery after a PC address change and character-specific official map completion remain unavailable. Cross-map route pathfinding is intentionally deferred.

See [architecture](docs/architecture.md), [account data](docs/account-data.md), [character stats](docs/character-stats.md), [protocol](docs/protocol.md), [map coordinates](docs/map-coordinates.md), and [development](docs/development.md).

Guild Wars 2 and ArenaNet are trademarks of their respective owner. This project is unofficial and is not affiliated with or endorsed by ArenaNet.
