# Development

## Bridge

The bridge targets .NET 10 LTS and uses ASP.NET Core’s built-in Kestrel/WebSocket support. QRCoder is the only non-test runtime package and is used solely to render pairing QR data in the console.

`MumbleLinkLayout` contains audited byte offsets instead of marshaling a C# struct. The parser performs length checks, treats GW2's unchanged `context_len` value of 48 as valid while reading extended fields from the fixed 256-byte context allocation, decodes fixed UTF-16LE buffers at a NUL pair, and tolerates empty/partially-written identity JSON. Tests construct raw little-endian bytes at those exact offsets.

Useful commands:

```bash
dotnet build bridge/GW2Bridge/GW2Bridge.csproj
dotnet test bridge/GW2Bridge.Tests/GW2Bridge.Tests.csproj
dotnet run --project bridge/GW2Bridge/GW2Bridge.csproj -- --simulate --port 38291
```

Do not add API-key arguments or endpoints to the bridge. Do not log pairing tokens after their deliberate one-time pairing display.

## iOS

`project.yml` is the project source of truth. Run `xcodegen generate` after adding files or changing target settings. Deployment target is iOS 17. The simulator has no camera QR scanner, so use manual bridge details or in-app simulation there.

The native renderer deliberately keeps overlays independent of `AsyncImage` tile success. A network error/404 therefore produces a neutral tile without moving or removing markers.

When adding API endpoints:

- use `GW2APIClient` so auth and error translation remain centralized;
- batch ID metadata requests (ArenaNet supports `ids=` lists; current item batch limit is 200);
- cache static metadata, but refresh account-owned data on demand;
- never include a key in a URL, log, UserDefaults, fixture, or WebView.

When adding gathering sources, implement `MarkerDataProvider`, preserve source/licence metadata, and do not treat a possible spawn as currently active.

## Validation matrix

| Capability | Automated here | Manual environment needed |
|---|---:|---:|
| Explicit Mumble buffer parsing | Yes | — |
| Protocol serialization/decoding | Yes | — |
| Stale tick detection | Yes | — |
| Coordinates/gathering/batching | Yes | — |
| iOS app compile | Yes | — |
| Real GW2 shared memory | No | Windows + GW2 |
| Physical QR camera/local network | No | iPhone + PC |
| Account API with a real key | No | User-owned API key |
| Tile completeness on all maps | No | Provider/content dependent |
