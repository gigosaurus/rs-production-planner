# Account mode comes from the game

Amends ADR 0008 and ADR 0011.

ADR 0008 saves Account mode for each character, and a new character starts with Account mode not ironman. Then the player must set it. `probes/account-mode-probe` found that the game gives it (#52). Now the plugin reads Account mode from the game. It does not save it.

## How the plugin reads it

The var `VarPlayer.IRONMAN` holds the account type as bit flags. Bit 0 is set for ironman, hardcore ironman and group ironman. The character is an ironman when bit 0 is set. `docs/client-behaviour.md` gives the tested values.

The value is correct when the plugin starts. A `VarTransmit` event gives each change.

## Saved data

The plugin does not save Account mode. The key `char:<displayName>:settings` is removed, because Account mode was its only setting. Recipe overrides can add a key when they need one. The plugin does not read an old `char:<displayName>:settings` key.

## GE amounts

For an ironman, the GE amounts of Make (ADR 0009) are always 0 (#52). `Made` needs no check for this. A GE amount comes only from GE offers, and an ironman cannot make a GE offer. The adapter then gives no offers, and each rise counts as made. This is not tested in the game, as ADR 0009 says for all GE behaviour.

## Considered Options

- **The player sets Account mode, and the plugin saves it (ADR 0008):** rejected. The game gives the correct value. A saved value can be wrong, for example after a player leaves ironman mode.
- **Read the var, and save a copy as a fallback:** rejected. The plugin plans only when the player is logged in, and the var is then available.
- **Keep an empty `char:<displayName>:settings` key:** rejected. It holds no data.
- **`Made` ignores GE offers for an ironman:** rejected. The check never runs, because an ironman has no GE offers.

## Consequences

The Settings of the Plan window has no Account mode control. If Jagex changes the bit flags, the plugin shows a wrong Account mode until we change it.
