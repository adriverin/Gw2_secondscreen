# Localization architecture

SwiftUI product strings use native localized string keys and can be extracted into an Xcode String Catalog. ArenaNet names/descriptions are fetched using the current language where the endpoint supports it. Bundled acquisition knowledge and fallback guidance are currently curated in English.

These are three distinct translation domains: Companion UI copy, ArenaNet-localized content, and Companion-curated factual content. Phase 6B prepares the first domain for catalog extraction but does not claim complete translations. Do not machine-translate ArenaNet or third-party content into the UI without explicit provenance and review.
