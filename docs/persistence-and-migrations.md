# Persistence and migrations

Credentials use Keychain. Downloaded metadata, account snapshots, Today snapshots, map/objective data, and icons use independently decodable cache files. A corrupt cache read becomes a miss; it does not trigger a whole-app wipe and does not delete user-authored state.

Goals use `GoalScopeSnapshot` schema 1 under `phase4.goals.v1.<scope>`. Sessions/preferences/history use `SessionPersistenceSnapshot` schema 1 under `phase5.session.v1.<scope>`. Objective history and route use their own versioned keys. Pairing v1 gained an optional `bridgeId`; decoding legacy v1 pairing without it remains supported and the next QR upgrades identity information.

Future incompatible model changes must either decode the old envelope into the current model or move to a new versioned key while preserving the old data until migration succeeds. Metadata corruption may discard only the affected cache. User-created goals/session history must not be treated as disposable cache.

Reset App explicitly deletes credentials, pairing, cache directories, local goals/session state, and preferences after confirmation. Clear Cached Game Data leaves credentials and user-authored data intact.
