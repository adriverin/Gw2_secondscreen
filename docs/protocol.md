# Telemetry protocol

The bridge exposes `GET /telemetry?token=<pairing-token>` as a WebSocket and sends UTF-8 JSON at 20 packets per second. `/health` is an unauthenticated non-sensitive liveness endpoint. Authenticated `GET /pairing/validate` returns `protocolVersion`, `bridgeVersion`, and stable `bridgeId` before the WebSocket is opened. The normative telemetry shape is [the JSON Schema](../protocol/telemetry.schema.json); [a v1 example](../protocol/examples/telemetry.v1.json) is shared with decoder tests.

`protocolVersion` is currently `1`. Consumers ignore unknown properties and reject unsupported protocol versions. Optional subobjects are `null` while GW2 is unavailable or before MumbleLink has a complete context.

Important state fields:

- `connected`: the bridge has a readable, complete GW2 MumbleLink snapshot.
- `positionAvailable`: the position is fresh and supported for the current game mode.
- `uiTick`: GW2 source tick, used to detect a mapping that remains present but stops updating.
- `timestampUnixMs`: bridge wall-clock send time, used for phone-side staleness.
- `player.continentX/Y`: authoritative flat-map location used by tiles and markers.
- `player.headingX/Y`: horizontal heading projected from Mumble avatar-front X/Z.
- `statusMessage`: a safe user-facing reason when the position is unavailable.

Mumble `uiState` bits currently exposed are map-open (bit 0), game-focus (bit 3), and combat (bit 6). Competitive mode (bit 4) suppresses live positioning rather than presenting unreliable movement.

## Pairing

At startup the bridge creates a 256-bit cryptographically random, Base64URL token. The QR payload is:

```json
{"version":1,"host":"192.168.1.42","port":38291,"token":"...","bridgeId":"0123456789abcdef..."}
```

The bridge compares the supplied token in constant time and returns 401 before upgrading invalid requests. Token and random bridge identity persist across normal bridge restarts; `--reset-pairing` or the R key rotates only the token. The identity is not derived from PC hardware. The iPhone stores the payload in Keychain and can distinguish the paired installation from a different bridge at the same address. Legacy v1 payloads without `bridgeId` remain decodable.

Unknown optional JSON fields are ignored. Optional compatible additions do not bump the version. A required or semantic incompatibility must bump `protocolVersion`; lower bridge versions produce “bridge too old,” while higher versions produce “app update required.”

## Security

MVP uses unencrypted `ws://` because local certificate provisioning would make pairing substantially more complex. The token authenticates subscribers but anyone controlling the LAN could observe traffic. Use a trusted private network; do not expose the bridge port to the internet. A future protocol can add TLS with a pairing-time certificate fingerprint while retaining the provider boundary.

The pairing payload never contains an ArenaNet API key. The bridge never accepts or stores one.
