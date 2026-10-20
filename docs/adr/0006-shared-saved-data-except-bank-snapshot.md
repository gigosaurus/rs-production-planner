# All characters share the saved data, except the Bank snapshot

Superseded by ADR 0008.

All characters share all saved data: the Plan, settings, Assumed stock, Reserves and Unlocks. We do not keep separate data for each character. Named plans will come later. They will cover more than one character in a simpler way.

The Bank snapshot is the one exception. It is a fact about the bank of one character. For this reason, it records the `displayName` that it came from. The Plan of a different character does not use it. That Plan shows "bank not seen yet" until that character opens their bank.

## Considered Options

- **Separate data for each character, keyed by `displayName`:** rejected. It needs more work now. Named plans will replace it.
- **Keyed by `Player.GetTrackingID()`:** rejected. It needs the `trackingAccess` permission. That permission needs a larger privacy declaration at submission.
