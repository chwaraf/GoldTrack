# GoldTrack — Addon Analysis for Future Changes

Session gold-per-hour tracker for TBC Classic Anniversary (`## Interface: 20505,20506`). This document is a working analysis of how the addon is built, what invariants it relies on, the bugs fixed in this pass, and the areas most worth touching next. It is meant to be a map for future work, not a changelog.

---

## 1. The core idea (read this first)

GoldTrack does **not** measure `GetMoney()` deltas, bag snapshots, or AH/vendor/mail cash-in. It estimates the **disposition value of world loot, frozen at the moment the item drops**:

```
loot event at time T  →  decide best disposition (AH net / DE / vendor / none)
                      →  credit unitCopper at T
                      →  gold/hour = Σ credited copper ÷ active session time
```

This is deliberate: "wrong g/h is worse than none." The value shown is what the loot *was worth when you got it*, not what you eventually sold it for. That means later transactions (vendoring, mailing, auctioning, DEing the same item) must **never** add a second credit. Most of the complexity in `Events.lua` exists to enforce that "no double credit" rule.

**Consequence for future work:** any change that credits more copper for something that was already counted (or credits value for something that wasn't world loot) silently inflates every number downstream (session, `Total`, best-session records, archives). Add/fix classifiers with that in mind.

---

## 2. File map and responsibilities

| File | Responsibility | Persists? |
| --- | --- | --- |
| `GoldTrack.toc` | Load order, interface, `SavedVariables` | — |
| `Core.lua` | Namespace `GT`, defaults, session state machine, clock, slash, keybinds, reset/wipe popups | Reads/writes `GoldTrackDB` + `GoldTrackCharDB` |
| `Money.lua` | Coins parse/format, `GPerHour`, elapsed/number formatting | — |
| `Prices.lua` | Price resolution (Auctionator/TSM/vendor), sell rate, cache | — |
| `Valuation.lua` | Rule engine: pick AH/DE/VENDOR/NONE from a resolved item | — |
| `Ledger.lua` | Session rows, incremental copper/items/method totals, archive, override | `GoldTrackCharDB.session` |
| `Events.lua` | Loot/money classifier, OPEN/DE suppression, bag tracking, NIT | — |
| `UI_HUD.lua` | Compact HUD + collapsed square, tooltip/menu | `GoldTrackDB.hudPoint` etc. |
| `UI_Main.lua` | Main window (Total/Session/Loot/Config), archive list | `GoldTrackDB.mainPoint/W/H` |
| `UI_Config.lua` | Config tabs and defaults widgets | — |

`SavedVariables`: `GoldTrackDB` (account-wide) and `GoldTrackCharDB` (per character). Session state (`state`, `activeMs`, `leavingAt`, `copper`, `rows`, `order`, `byMethod`) lives in `GoldTrackCharDB`. `GetTime()`/`segmentStart` are **never** persisted.

---

## 3. The session clock

- **State machine:** `STOPPED` ⇄ `RUNNING`. `GT.afkPaused` is a runtime flag that folds the segment when AFK (if `pauseWhenAFK`) without stopping.
- **Segments:** `activeMs` is accumulated copper-only-when-running. A single "segment" (`segmentStart`) is folded on AFK, leave-world, logout, stop.
- **Reload vs logout:** `PLAYER_LOGOUT` (which also fires on `/reload`) records `leavingAt`. `ADDON_LOADED` compares the gap: short (`≤ RELOAD_GAP=60s`) + `resumeAfterReload` ⇒ keep `RUNNING`; otherwise honor `resumeAfterLogout`.
- **`GT.NowMs()`** returns clamped live time and is the single source for elapsed time in HUD and g/h.

**Future risk:** the reload/logout distinction is heuristic (time gap). If a player crashes and relogs fast, the session may "resume" on a fresh character/zone. Consider recording `zone`/`character` at segment start and refusing to resume across a character switch (a `/reload` is same character; a relog may not be).

---

## 4. The loot classifier (`Events.lua`)

Event-driven, no combat-log parsing. Registered only while a session is live (`SetListen`).

| Signal | Handled as |
| --- | --- |
| `CHAT_MSG_LOOT` | `LOOT_ITEM_SELF`/`_MULTIPLE` (always), `_PUSHED_SELF` (only near loot frame / gather / quest), `_CREATED` (ignored) |
| `CHAT_MSG_MONEY` | `YOU_LOOT_MONEY` / `LOOT_MONEY_SPLIT` → `CreditGold` |
| Bag changes | only for OPEN transforms (clams) and farmed-DE-gear detection |
| `UNIT_SPELLCAST_*` | arms the destroy window for DE/prospect; gather spells set a 3s window |
| `GET_ITEM_INFO_RECEIVED` | resolves stuck `PENDING` rows |

**Openables (clams):** a pending queue (`pendingOpen`). Items looted → credited; when the count of an openable in bags drops, an OPEN is assumed and the pending row is *replaced* by its contents (the clam's copper is basically never counted). Timeout (`OPEN_TTL=2s`) rolls back the pending row. **This is the most fragile area — it depends on the *loot frame* owning the openable's content and on `BAG_UPDATE` timing.** Under load/log-suffix delays the "hadLootFrame / ownsFrame / decremented" dance can mis-credit. Worth a focused test pass.

**DE/prospect suppression.** The addon never wants DE reagent loot (dust/essence/shards/crystals) counted as world loot. It suppresses when:
1. a DE/prospect cast was seen recently (`destroyUntil`), or
2. the Enchanting trade skill is open (`encWindowUntil`), or
3. session-farmed DE-able gear left the bags (`markDestroy("farmed gear left bags")`).

That last one (3) only fires for gear that is already in the session rows (`sessionGearIDs`). Any gear DE'd that was **not** counted in this session (carried over a relog, or from a previous session) is covered only by (1). That's why the spell-cast handler mattered so much (see §6).

---

## 5. Valuation invariants (`Valuation.lua`)

`GT.ValueItem(info, soulbound)` returns `{method, unitCopper, why, ...}`:

- **Grey (q=0)** → always `VENDOR`.
- **BoP/soulbound** → never AH; DE only if this char can enchant and `de ≥ vendor+1g`, else vendor, else `NONE 0`.
- **Mat track** (not DE-able, stack>1 or recipe) → AH if `ahNet ≥ 3×vendor` **or** `≥ vendor+1g` (vendor 0 ⇒ just +1g); else vendor.
- **Gear (DE-able)** → AH if `ahNet ≥ vendor+10g` **and** `≥ de+8g`; else DE if `de ≥ vendor+1g`; else vendor.

AH net uses configurable mode. Default `if_sold`: `ahRaw - 5% - deposit×(1-p)`. Unknown sell rate forces `if_sold` so a 50% guess does not haircut.

**Invariant:** `unitCopper` is frozen **at loot time**; later `/gt refresh` only updates `sellRate`/`soldPerDay`/`source`, never rewrites gold or method (except the deliberate "stuck PENDING" heal). Keep `ValueItem` pure (given `info` and `soulbound`, return the same verdict) so `SelfTest` fixtures stay authoritative.

---

## 6. Bugs fixed in this pass

### a) DEing bag items added gold after a relog (root cause: wrong spellcast argument)
`UNIT_SPELLCAST_SUCCEEDED` on TBC Classic fires `(unit, castGUID, spellID, castBarID)`. The old handler did `local spellId = c` — but `c` is **castBarID**, not the spellID (which is in `b`). So the DE/prospect detection (`13262`/`31252`) never matched, the destroy window was never armed, and the dust/essence/shards that a DE produced were credited as world loot. It was most visible *after a relog* because `encWindowUntil`/`destroyUntil` reset to `0` on reload, leaving the spell-cast path as the only guard for gear that wasn't in the session rows.

**Fix:** rewritten `handleSpellCast` reads the spellID from the correct arg (`b`), also accepts the legacy `(unit, spellName, rank, lineID, spellID)` form (`a`/`e`), and falls back to the localized spell name. Gather-spell detection preserved.

### b) HUD GOLD showing `xx…` instead of a number
The top-right **GOLD** value slot is 13px in a 52px-wide FontString. Once the session total passes ~1000g the comma-separated string (`12,345.67`) is wider than the slot and gets clipped. Added a `setFit` helper that shrinks the font until the text fits (and restores it when short), applied to `GOLD` and `G/h`. Hardened `commaNum` against non-finite/odd values so it can never render `nan`/`inf`/garbage.

### c) Right-click Reset → clear without saving
Previously every reset went through `GOLDTRACK_RESET` ("Archive this session into Total and clear?"). Added `GOLDTRACK_CLEAR` ("…WITHOUT archiving…") and made **right-click** on the HUD Reset button (and the main-window Reset button) show it; **left-click** keeps the archive-then-clear behavior. Tooltips updated on both. `GT.SessionReset(noArchive)` now skips `ArchiveCurrent` when `noArchive` is true.

---

## 7. Known gaps / ideas for future changes

Ranked roughly by value/cost. The "quick wins" are small; the "projects" are larger.

### Quick wins
1. ✅ **Auto-fit is applied to every HUD value cell** (TIME, hourly NIT count, GOLD, G/h, G/m), not just GOLD/G/h. All use `setFit`, which shrinks the font to the cell width and restores it when short. Tradeoff: font size can vary between cells, and if a value is astronomically large it still bottoms out at a minimum size — so the big slots (G/h, GOLD) are the ones that matter most. This mirrors the collapsed-square button, which already did the same thing.
2. **Expose a "clear without saving" slash command** (e.g. `/gt wipe-session` or `/gt reset!`) and a binding, so right-click is not the only way.
3. **Add a "discard session" option to the HUD right-click menu** (currently `Reset session` always archives).
4. **`GT.SessionReset` noArchive wording:** make the dialog show what's being discarded (copper, items, time) so an accidental right-click is obviously destructive.

### Medium
5. ✅ **Session identity on resume.** `GT.CharacterKey()` (`UnitFullName@realm`) is stored on `SessionStart` (`session.unit`) and checked in `OnEnteringWorld`: if a `RUNNING` session is found under a different character, it is stopped instead of resumed. Backward compatible (legacy sessions have no `unit` and are not stopped). `GoldTrackCharDB` is per-character, so this is insurance more than a bug fix — a real character switch loads a fresh, `STOPPED` DB.
6. **Confirm `UNIT_SPELLCAST_*` payload in a live 2.5.5 test** (the fix handles both forms, but a definitive capture would let you drop the legacy branch). Add a `/gt debug` line that prints the raw args on the first DE cast.
7. **Openable (clam) flakiness.** Add an explicit integration test for: loot frame open + open + contents present; loot frame open + open + no frame; and bag-count-only OPEN. The `pendingOpen`/`hadLootFrame`/`ownsFrame`/`decremented` lattice is where subtle double-credit bugs live.
8. **DE reagent coverage audit.** `DE_REAGENT` is a hardcoded ID list. Confirm every TBC DE output is present, or replace with a runtime check ("is this item a known reagent of spell 13262") via `GetItemInfo`/`C_Spell.GetSpellItemReagent` if the client exposes it.

### Larger projects
9. **Persist per-zone / per-dungeon breakdown.** You already sit on NIT zone changes and have `zone` on archives. A per-zone g/h view is a natural extension and cheap to derive from archives.
10. **Better "stuck PENDING" handling.** Currently a row that never resolves is healed on `/gt refresh`. Consider resolving it lazily on HUD tick when the item info arrives, and marking it in the Loot list so the user knows it was late-valued.
11. **Bag-snapshot-based guard rail.** The fear motivating the design is double-credit. An optional "audit" mode that compares session copper against a full bag+AH+mail snapshot at start and stop could flag drift, but it is a big behavioral change — keep it opt-in.

---

## 8. Test surface

- `/gt selftest` → runs the real `ValueItem` against baked fixtures (must keep passing; add new fixtures when changing thresholds).
- `/gt debug` → prints classifier trace lines; the DE cast fix should be verified with this.
- Manual scenarios worth re-run after any change:
  - Loot a load-out of mats and De-able gear, `/gt start`, then DE everything → dust must **not** appear in the Loot tab.
  - `/reload` mid-session, then DE a green that was in your bags before the session → must **not** add gold.
  - Right-click Reset → must discard without touching `Total`; left-click Reset → must archive into `Total`.
  - Loot a clam with and without the loot frame open → contents counted, clam not double-counted.
