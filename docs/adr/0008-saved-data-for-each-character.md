# Save data for each character, but keep Plans global

Supersedes ADR 0006.

The plugin keys saved data by `displayName`. Data that is a fact about one character, or that the plugin measures on one character, is saved for each character:

- Bank snapshot
- Assumed stock, and the last Detected counts that the plugin uses to measure its rises (ADR 0004)
- Reserves
- Unlocks
- Account mode
- Recipe overrides
- Made counts, and the amounts that the plugin uses to calculate them

Data that says what to make and how to plan it is global:

- the Plan (later the named Plans) and its Targets
- Target mode
- Made count scope
- Planning mode

One player can have a normal main and an ironman alt, with different quests and levels. Shared Account mode, Unlocks and Recipe overrides give a wrong Plan on one of them. Made counts must also be separate for each character.

A character that the plugin has not seen starts with Account mode not ironman, and with no Assumed stock, Reserves, Unlocks or Recipe overrides. Its Made counts start at 0.

## Considered Options

- **Share all data except the Bank snapshot (ADR 0006):** rejected. Made counts must be separate for each character. Account mode, Unlocks and Recipe overrides are wrong on a second character.
- **Keyed by `Player.GetTrackingID()`:** rejected again. It needs the `trackingAccess` permission. That permission needs a larger privacy declaration at submission.

## Consequences

When a player changes their name, the plugin does not know the new name. That character starts again with no saved data. Names change rarely, so we accept this.
