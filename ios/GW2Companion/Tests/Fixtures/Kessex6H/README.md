# Kessex geography regression tiles

Original 256×256 ArenaNet JPEGs retrieved 2026-10-01 from
`https://tiles.guildwars2.com/1/1/7/{x}/{y}.jpg`.

Parent z6 (87,61) uses (174,122), (175,122), (174,123), (175,123).
The eastern neighbor (88,61) uses x176–177/y122–123.
The southern neighbor (87,62) uses x174–175/y124–125.

Tests compare each oriented child and both sides of every internal and neighbor
boundary against a separately rendered, upright UIKit reference. Synthetic tiles
also include directional features; flat quadrant colors alone cannot detect a
vertically reversed child image.
