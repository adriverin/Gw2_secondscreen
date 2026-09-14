# Personal Tyria Session Planner

The planner is a deterministic, local, read-only heuristic. It does not spend resources, place
Trading Post orders, craft, send game input, or claim optimal gameplay or exact durations.

## Phase 6A Today integration

The existing planner now receives both goal-derived needs and `AccountOpportunity` values in one `SessionPlanningContext`:

```text
Goals ────────────────┐
Today opportunities ──┼─ SessionPlanner ─ SessionTask[]
Current map ───────────┤
Preferences ───────────┘
```

`SessionTaskSource` records a goal, opportunity, multiple goals, or a mixed source. Daily crafting cross-benefit uses only the reviewed opportunity-to-item ID mapping. When an incomplete daily craft has the same item target as a goal craft candidate, the planner emits one task and explains both benefits.

Today score contributions are deterministic and appear in “Why this?”:

| Factor | Score |
| --- | ---: |
| Daily opportunity | +40 |
| Weekly opportunity | +20 |
| Seasonal opportunity | +5 |
| Ready-to-claim Vault reward | +70 |
| API progress at least 75% complete | +15 |
| Preferred Today activity | +20 |
| Avoided Today activity | -25 |
| Same validated current map | +50 |
| Structured goal + opportunity cross-benefit | +60 |

These combine with the documented Phase 5 goal/acquisition factors. Daily urgency is an advantage, not a claim of optimality; a high-priority goal can still outrank a daily task. Activity avoidance changes rank but does not hide dashboard data.

No task duration is invented. The Session duration remains a task-count planning horizon.

Active sessions capture an optional `TodayProgressSnapshot` alongside the holdings snapshot. “Refresh Progress” refreshes account and Today data, then stores the latest factual snapshot. Session history reports count changes as “changed during this session”; it does not attribute causality.

## Pipeline

```text
Active goals
  -> typed unmet requirements
  -> acquisition knowledge
  -> candidate actions
  -> cross-goal consolidation
  -> map/account/market context
  -> inspectable scoring
  -> finite session plan
```

Crafting requirements are consolidated by target before account supply is subtracted. This is
important: if two goals need 20 and 30 Mithril and the account owns 10, the combined shortage is
40, not two separately calculated shortages. Candidate identity includes method, target, and map
context. User-linked map objectives consolidate by objective ID.

Actual score constants live in `SessionScoring`. Version 1 uses highest goal priority (+15/+35/
+60), +20 per additional helped goal, +50 for the current map, +30 for the nearby band, +80 for a
globally preferred method, +80/-80 for an explicit choice, +35 for ready crafting, +10 for a
loaded sell offer, -30 for an avoided method, and -10 for manual verification. Every applied
factor becomes a `ScoreContribution`; task detail displays the exact sum and explanation.

Preference precedence is deterministic:

1. requirement-specific override
2. goal/target override
3. global method preference
4. neutral default

Avoid changes rank, not availability. Alternatives remain inspectable.

Duration is a planning horizon used only to cap the initial number of tasks (3/5/7/9 for 15/30/
45/60 minutes). It is not a completion-time estimate.

Starting a plan persists an `ActiveSession` with its task list, goal links, initial map/player
context, and only relevant item/currency quantities. Navigation and gathering tasks hand trusted
objective IDs or exact user/curated coordinates to the existing Phase 3 navigation engine.
Map-only knowledge opens map context without inventing a pin.

Gather/navigation proximity can establish a Companion visit, not a yield. Craft and buy tasks
are not completed merely by opening them. Explicit account refresh produces a factual before/
after quantity diff. The summary says quantities changed and does not infer whether they were
gathered, bought, crafted, consumed, or moved.

Replanning is explicit. It regenerates pending candidates from current holdings and map context,
preserves locked work, and keeps completed/visited/skipped decisions from reappearing during the
same session. A map change prompts the player to update or keep the plan; telemetry frames do not
rebuild candidates.

Completed session summaries store dates, horizon, task counts, goals helped, maps/objectives
visited, and relevant account diffs. History stays on device.
