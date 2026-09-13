# Navigation engine

## Distance, bearing and direction

Navigation uses the same continent-coordinate points as telemetry and the map renderer. Coordinate distance is Euclidean:

```text
distance = sqrt((target.x - player.x)^2 + (target.y - player.y)^2)
```

The value is intentionally labeled **coordinate units**, not meters. Bearing is clockwise from map north. Because continent Y increases toward screen south, the implementation uses `atan2(deltaX, -deltaY)` and normalizes the result to 0–360 degrees. Bearings are grouped into eight 45-degree cardinal sectors: N, NE, E, SE, S, SW, W and NW.

Relative heading is an optional display enhancement calculated from the live player heading. Absolute cardinal direction and the map remain authoritative.

## Proximity and arrival

`ObjectiveProximityEngine` receives the player point, locally visible objectives and current target. It returns sorted Nearby entries, newly entered arrival radii and a target-arrival event. Evaluations are limited to four times per second unless the player has moved at least four coordinate units. View code does not independently sort or detect arrival.

Arrival radii vary by objective type. An objective fires only when crossing from outside to inside its radius; remaining inside does not repeat the event. Arrival records `visited` in Companion history. It never records ArenaNet completion or manual completion.

## Route generation and playback

Automatic generation starts at the current player position and repeatedly selects the nearest remaining visible/filter-matched objective. Equal distances use the stable objective ID as a deterministic tie-break. This is a nearest-neighbor **suggested order**; it is not advertised as a fastest route.

Routes are queues of `MapObjectiveID` values with a current index. Starting selects the first target. Arrival advances when Auto-advance is enabled. Previous, Next, Skip, reorder, remove and Stop operate on the same route model. If a route references an objective not present on the active map, navigation pauses with an instruction to travel to that map in Guild Wars 2.

The target line is a straight direction indicator only. The app has no navigation mesh, terrain elevation, portal graph or traversal rules. Mountains, cliffs, underground levels and map transitions can make the geometric order impractical.

## Rendering and performance

The existing grid-indexed marker scene now accepts unified objectives. Only viewport buckets are hit-tested or rendered. Far zoom levels retain targets, waypoints and mastery markers while suppressing dense secondary markers; nearer zooms cap a single render pass defensively. Official icons share the existing memory/disk cache. Telemetry can continue at 10–20 Hz while proximity sorting is throttled.
