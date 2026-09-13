# Character stat calculations

## What Phase 2 calculates

`CharacterStatEngine` produces **Equipment Attributes**. It deterministically sums attribute modifiers exposed by the account/static APIs from:

- the equipped item's selected `stats.attributes` values, when present;
- the item's static infix attributes when no selected values override them;
- resolved upgrade item infix attributes; and
- resolved infusion item infix attributes.

The first displayed attributes are Power, Precision, Ferocity, Toughness, Vitality, Condition Damage, Expertise, Concentration, and Healing Power. Unknown attribute keys remain representable in the engine even when the current summary UI does not prioritize them.

## What it does not calculate

The view does not claim to reproduce the live Hero Panel. It does not add level-80 base attributes or modifiers that cannot be proven complete from the returned payload, including:

- selected trait effects and conditional bonuses;
- boons, temporary effects, transformations, or encounter effects;
- food and utility consumables;
- profession mechanics whose values depend on game state;
- PvP/WvW normalization and game-mode-specific coefficients; or
- effects described only in prose.

For that reason the UI labels the result **Equipment Attributes** and explains that it can differ from the in-game Hero Panel. Future sources can be added behind `CharacterStatEngine` without changing equipment views or overstating existing accuracy.

## Determinism and testing

Tests use local equipment/item fixtures with selected stats, an upgrade, and an infusion. They assert exact summed values and require no API key or live game session.
