# GW2 Companion

GW2 Companion is an unofficial, local-first iPhone second screen for Guild Wars 2. Its home screen follows the character on a pan/zoom map, shows an oriented player marker, and overlays configurable sample gathering locations. The same app talks directly to the official Guild Wars 2 API for characters, inventory, materials, bank, shared inventory, and wallet data.

Live position does **not** come from the GW2 web API:

```text
Guild Wars 2 → MumbleLink → Windows bridge → authenticated LAN WebSocket → iPhone map
ArenaNet API ───────────────────────────────────────────────────────→ iPhone account views
```

The bridge never receives the ArenaNet API key. The iPhone stores API and bridge credentials in Keychain. There are no user accounts, analytics, cloud service, or location/GPS permission.

## Requirements

- Xcode 26 or newer and XcodeGen to build the iOS 17+ app
- An iPhone/iPad on the same LAN as the Windows PC (the simulator also supports in-app mock mode)
- Windows with the .NET 10 SDK/runtime
- Guild Wars 2 for real telemetry
- Optional ArenaNet API key with `account`, `characters`, `inventories`, and `wallet` permissions

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

If Guild Wars 2 is launched with a custom `-mumble NAME` option, give the bridge the same name:

```powershell
dotnet run --project bridge/GW2Bridge/GW2Bridge.csproj -- --mumble-name NAME
```

Remove `-mumble 0`, which disables MumbleLink. Run the bridge and the game as the same Windows user and at the same elevation level (normally, neither should be run as administrator).

Use another port with `--port 40000`.

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
5. A bad or missing token receives HTTP 401. Restarting the bridge creates a new random token, so pair again.

MVP LAN traffic is plain `ws://`, so use it only on a network you trust. The random token prevents unauthenticated subscriptions but does not encrypt character/location data; see [protocol security](docs/protocol.md#security).

## Connect a GW2 account

Open Account and paste a key created at [ArenaNet account applications](https://account.arena.net/applications). The app validates it with `/v2/tokeninfo`, saves it only after validation, and lists granted permissions. Missing optional permissions disable only the affected data. Pull to refresh account screens.

## Test the bridge

```bash
dotnet test bridge/GW2Bridge.Tests/GW2Bridge.Tests.csproj
dotnet publish bridge/GW2Bridge/GW2Bridge.csproj -c Release -r win-x64 --self-contained false
```

## Real GW2/MumbleLink validation

This environment was macOS and could not perform real MumbleLink validation. On Windows:

1. Launch Guild Wars 2 and enter the world on a non-competitive map.
2. Run the bridge without `--simulate`.
3. Pair the phone and confirm the character, map ID, and coordinates update while moving.
4. Stop GW2 and confirm **GW2 NOT RUNNING**; restart it and confirm recovery.
5. Stop the bridge and confirm **PC OFFLINE**, followed by automatic reconnection after restart/re-pairing.
6. Enter a competitive map and confirm the marker does not falsely move when continent position is unavailable.

## Limitations

- Real MumbleLink was implemented and parser-tested, but not executed against Guild Wars 2 in this macOS environment.
- The official tile artwork can be outdated or missing for newer maps. The app keeps overlays usable on a neutral background.
- Live position requires the Windows bridge; `/v2` has no live coordinates.
- Competitive maps can restrict useful continent-position telemetry.
- Bundled gathering points are original synthetic samples, not guaranteed or verified spawns.
- “Visited” means the player entered a radius, not that the node was harvested; session visits reset on app relaunch.
- MVP WebSocket transport is authenticated but not TLS-encrypted.
- Bonjour discovery, TacO/Blish import, routes and map POIs are intentionally deferred.

See [architecture](docs/architecture.md), [protocol](docs/protocol.md), [map coordinates](docs/map-coordinates.md), and [development](docs/development.md).

Guild Wars 2 and ArenaNet are trademarks of their respective owner. This project is unofficial and is not affiliated with or endorsed by ArenaNet.
