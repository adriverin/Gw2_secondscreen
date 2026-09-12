# Map coordinate systems

## Spaces

1. **Avatar coordinates** are MumbleLink 3D world values (`fAvatarPosition`). They are retained for future overlays but are not used to place the MVP marker.
2. **Map coordinates** are a map-local system bounded by `/v2/maps/{id}.map_rect`. Their Y axis is opposite the rendered continent rectangle.
3. **Continent coordinates** are flat global pixel-like coordinates. Mumble context `playerX/playerY`, `/v2/maps.continent_rect`, gathering nodes, and maximum-zoom tile pixels share this space. This is the MVP’s canonical space.
4. **Tile coordinates** select a 256×256 image at an integer zoom from the tile service.
5. **TacO world coordinates** use Mumble's 3D meter units. Gathering marker `xpos` maps east/west and `zpos` maps south/north; both are converted to game inches (`×39.37007874`) and Z is negated before the normal map-to-continent transform.

All formulas live in `GW2CoordinateTransformer`; views must not add correction constants.

## Map-local ↔ continent

Let `m0`, `m1` be `map_rect` corners and `c0`, `c1` be `continent_rect` corners. For a continent point `c`:

```text
nx = (c.x - c0.x) / (c1.x - c0.x)
ny = (c.y - c0.y) / (c1.y - c0.y)

map.x = m0.x + nx       * (m1.x - m0.x)
map.y = m0.y + (1 - ny) * (m1.y - m0.y)
```

The explicit `1 - ny` is the Y-axis inversion. The inverse is:

```text
nx = (map.x - m0.x) / (m1.x - m0.x)
ny = 1 - (map.y - m0.y) / (m1.y - m0.y)

continent.x = c0.x + nx * (c1.x - c0.x)
continent.y = c0.y + ny * (c1.y - c0.y)
```

Rectangle shape and zero extents are validated before division. Coordinates are intentionally not clamped in this transformation, so diagnostics can reveal an out-of-bounds source instead of silently moving a marker to an edge.

## Continent ↔ tiles

The official maximum zoom is modeled as `7`; at that zoom one continent unit maps to one tile pixel. At zoom `z`:

```text
scale  = 2^(7 - clamp(z, 0, 7))
pixelX = continentX / scale
pixelY = continentY / scale
tileX  = floor(pixelX / 256)
tileY  = floor(pixelY / 256)
localX = pixelX mod 256
localY = pixelY mod 256
```

The renderer uses the same `scale` to position the player and gathering markers relative to its center. Tile Y grows downward, matching continent rendering. Only conversion to/from map-local space inverts Y.

## Debug checklist

- Wrong map artwork: verify `continent_id` and `default_floor` from map metadata.
- Constant offset: inspect the raw context `playerX/playerY`; do not patch the view.
- Mirrored north/south: ensure inversion occurs only for map-local conversions.
- Correct at zoom 7 but wrong elsewhere: verify `2^(7-z)` and 256-pixel tiles.
- Correct overlay but blank art: the provider may legitimately return 404 for newer content.
