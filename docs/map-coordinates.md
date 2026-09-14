# Map coordinate systems

## Spaces

1. **Avatar coordinates** are MumbleLink 3D world values (`fAvatarPosition`). They are retained for future overlays but are not used to place the MVP marker.
2. **Map coordinates** are a map-local system bounded by `/v2/maps/{id}.map_rect`. Their Y axis is opposite the rendered continent rectangle.
3. **Continent coordinates** (`ContinentCoordinate`) are current ArenaNet continent coordinates. Mumble context `playerX/playerY`, `/v2/maps.continent_rect`, gathering nodes, and official POIs share this space. This is the app’s canonical overlay/navigation space. Origin is northwest; X increases east; Y increases south.
4. **Tile-world coordinates** (`TileWorldCoordinate`) are the pixel space of official `tiles.guildwars2.com` artwork at the projection **reference zoom**. They are a distinct type so current continent coordinates cannot be treated as tile indices by accident.
5. **Tile indices** select a 256×256 JPEG at an integer zoom (`z/x/y`).
6. **TacO world coordinates** use Mumble's 3D meter units. Gathering marker `xpos` maps east/west and `zpos` maps south/north; both are converted to game inches (`×39.37007874`) and Z is negated before the normal map-local transform.

Map-local ↔ continent formulas live in `GW2CoordinateTransformer`. Continent ↔ tile-world ↔ `z/x/y` formulas live in `ArenaNetTileProjection`. Views must not add correction constants.

## End of Dragons history

When End of Dragons expanded Tyria, current API continent coordinates moved:

```text
CURRENT TYRIA X = LEGACY X + 32768
CURRENT TYRIA Y = LEGACY Y + 16384
```

That shift is already present in live `/v2/maps.continent_rect`, Mumble context, and official POI `coord` values. Overlay math stays in current continent space.

Official `tiles.guildwars2.com` Tyria imagery now uses **current** continent coordinates. Empirically, subtracting the EoD shift projects Kessex Hills onto empty ocean. The projection therefore uses an identity continent → tile-world mapping for Tyria (`usesLegacyTileOrigin = false`). The shift remains available as `EndOfDragonsShift` for diagnostics and must not be applied to player, POI, gathering, or navigation coordinates.

## Tile zoom basis

`/v2/continents/1.max_zoom` is currently `8`, but official zoom-8 tile URLs 404. The historical ArenaNet tile grid is 1:1 with continent units at **zoom 7**.

```text
user-visible zoom              = selected tile zoom
projection reference zoom      = 7 for Tyria (not API max_zoom)
scale                          = 2^(referenceZoom - z)
tileWorld                      = continent   // Tyria official tiles
pixelX                         = tileWorld.x / scale
tileX                          = floor(pixelX / 256)
```

Using API max zoom 8 at user zoom 7 halves the tile indices and places Core Tyria markers over ocean northwest of the painted map. Marker scale uses the same reference zoom so overlays stay locked to tiles.

## Map-local ↔ continent

Let `m0`, `m1` be `map_rect` corners and `c0`, `c1` be `continent_rect` corners. For a continent point `c`:

```text
nx = (c.x - c0.x) / (c1.x - c0.x)
ny = (c.y - c0.y) / (c1.y - c0.y)

map.x = m0.x + nx       * (m1.x - m0.x)
map.y = m0.y + (1 - ny) * (m1.y - m0.y)
```

The explicit `1 - ny` is the Y-axis inversion. It is the only Y inversion in the pipeline. UIKit/CoreGraphics Y also increases downward, matching continent Y, so the native renderer does not invert again.

The inverse is:

```text
nx = (map.x - m0.x) / (m1.x - m0.x)
ny = 1 - (map.y - m0.y) / (m1.y - m0.y)

continent.x = c0.x + nx * (c1.x - c0.x)
continent.y = c0.y + ny * (c1.y - c0.y)
```

Rectangle shape and zero extents are validated before division. Coordinates are intentionally not clamped in this transformation, so diagnostics can reveal an out-of-bounds source instead of silently moving a marker to an edge.

## Wrapping and coverage

Tile X/Y **never wrap**. Negative indices and indices outside the continent grid return no tile. Missing/404 tiles are a neutral placeholder. Maps whose current `continent_rect` does not intersect known painted artwork show `Map artwork unavailable for this area` while player, POIs, gathering, and navigation remain.

Viewport fit uses the map’s **current** `continent_rect`. That rectangle is projected independently into tile-world space.

## Debug checklist

- Overlay markers agree with each other but artwork is ocean: check reference zoom (must be 7 for Tyria) before touching Mumble or POI coordinates.
- Constant overlay offset: inspect raw context `playerX/playerY`; do not patch the view.
- Mirrored north/south: ensure inversion occurs only for map-local conversions.
- Blank art on a Core Tyria map: provider 404 or coverage miss, not a coordinate bug.
- Newer expansion map: prefer missing artwork over pulling unrelated Core Tyria ocean tiles.
