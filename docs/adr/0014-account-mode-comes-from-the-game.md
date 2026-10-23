# Account mode comes from the game

Amends ADR 0008 and ADR 0011.
Amended by ADR 0015 (Effects).

In ADR 0008, the plugin saves Account mode for each character. A new character starts with Account mode not ironman. Then the player must set it. `probes/account-mode-probe` (#70) found that the game gives Account mode. Now the plugin reads Account mode from the game. It does not save it.

## How the plugin reads it

The var `VarPlayer.IRONMAN` holds bit flags. Bit 0 is set for ironman, hardcore ironman and group ironman. The character is an ironman when bit 0 is set. `docs/client-behaviour.md` gives the tested values.

When the plugin starts while the player is logged in, the value is correct. A start before login is not tested. A `VarTransmit` event gives each change.

## Saved data

The plugin does not save Account mode. The key `char:<displayName>:settings` is removed, because Account mode was its only setting. Recipe overrides can add a key when they need one. The plugin does not read an old `char:<displayName>:settings` key. An old key stays in PersistentDB, because the plugin never deletes saved data without a prompt (ADR 0011).

## GE amounts

For an ironman, the GE amounts of Make (ADR 0009) are always 0 (#52). `Made` needs no check for this. A GE amount comes only from GE offers. An ironman cannot make a GE offer. Thus the adapter gives no offers, and each rise adds to the Made count. This is not tested in the game, as ADR 0009 says for all GE behaviour.

## Considered Options

- **The player sets Account mode, and the plugin saves it (ADR 0008):** rejected. The game gives the correct value. A saved value can be wrong, for example when a character stops being an ironman.
- **Read the var, and save a copy for when the var is not available:** rejected. The plugin plans only when the player is logged in. The var is then available.
- **Keep an empty `char:<displayName>:settings` key:** rejected. It holds no data.
- **`Made` ignores GE offers for an ironman:** rejected. The check never runs, because an ironman has no GE offers.

## Consequences

The Settings of the Plan window has no Account mode control. If Jagex changes the bit flags, the plugin shows a wrong Account mode until we change the code.
