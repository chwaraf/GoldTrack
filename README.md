# GoldTrack — Classic Era & TBC Anniversary

Session gold-per-hour tracker for **Classic Era (1.15.x)** and **TBC Anniversary (2.5.5 / 2.5.6)**, from a single package. `## Interface: 20505, 20506, 11507, 11508, 11509`.

Copy the `GoldTrack` folder to the client's addons directory:

- TBC Anniversary: `World of Warcraft/_anniversary_/Interface/AddOns/GoldTrack`
- Classic Era: `World of Warcraft/_classic_era_/Interface/AddOns/GoldTrack`

The addon auto-detects which client it is running on (`WOW_PROJECT_ID`, falling back to the interface number) and applies the right economy defaults for that client (see **Client profiles** below).

Optional: **Auctionator** and/or **TradeSkillMaster**. Without them, only vendor prices are used. Region sell rates need the **TSM Desktop App + Anniversary AppHelper**, not just the in-game addon.

No Ace3.

---

## What g/h is

Estimated **disposition value of world loot**, frozen at the moment of loot. It is **not** `GetMoney()` delta, bag snapshots, or AH/mail/vendor cash-in.

Wrong g/h is worse than none. Credits come from classified chat loot only. Bags are used only for OPEN/DE transforms (clams, etc.).

Vendoring, mailing, trading, AH payouts, and disenchanting already-looted gear do **not** add a second credit.

## Client profiles

GoldTrack behaves differently per client because the **gold resolution** differs. Classic Era prices are roughly 5–10× smaller than TBC, so the valuation thresholds ("does AH beat vendor by X?", "does DE beat vendor by X?") must be much smaller on Era or nothing ever routes to AH/DE.

The detected client is shown at the top of the Config tab. When the client changes, GoldTrack swaps in that client's defaults **and remembers your own per-client tweaks**, so a tuned Era setup isn't overwritten by logging into TBC and vice versa. A "Reset thresholds to <client>" button (or `/gt reseteconomy`) restores the detected client's defaults.

| | TBC / Anniversary | Classic Era |
| --- | --- | --- |
| AH beats vendor by | 10g | 1g |
| AH beats DE by | 8g | 1g |
| DE beats vendor by | 1g | 10s |
| Mats: or vendor + | 1g | 10s |
| HUD min level | 70 (min-level hide on) | 1 (min-level hide off) |
| Auction durations | 12h / 24h / 48h | 2h / 8h / 24h |
| Deposit preset | 24h / 30% | 8h / 30% |

`/gt version` prints the detected client and max level. Future clients (WotLK, Cata, Mists) are detected and default to keeping current values until tuned.

## HUD visibility

The HUD is shown **by default on both clients**. On Classic Era the "hide below min level" gate is **off by default** (`hudMinLevelOn = false`), so the HUD always displays; on TBC it's **on** (defaults to hiding below level 70). Turning the HUD on manually always forces it visible — `/gt hud`, the HUD right-click **Show HUD**, and the Config **Show HUD** checkbox all override the min-level gate, so an explicit show always works. If you don't see the HUD, run `/gt hud` (now forces it on) or `/gt hudpos` to snap it back under the minimap.

---

## HUD

Default position: under the minimap (`MinimapCluster` / `Minimap`, 8px gap). Drag to move. Right-click for lock / reset / hide / config. Click empty HUD area to toggle the main window.

Layout (158x164):

- Chrome: **Loot** (opens Loot tab) | **T A N** (TSM / Auctionator / NovaInstanceTracker; green loaded, red missing) | **x** (hides HUD; `/gt hud` to show)
- **TIME** | unlabeled NIT count | **GOLD** (session estimate, gold with 2 decimals)
- Every numeric value auto-shrinks its font to fit its cell (large totals never clip; short values restore the normal size).
- Unlabeled hourly count between TIME and GOLD (no LOCK word): `3/5` white if slots left; at 5/5 a **red** `m:ss` until the oldest hourly instance frees; `-` if NIT missing. Mouseover tooltip has details plus NIT per-instance expiry lines.
- Count is **NovaInstanceTracker only**: `NIT:getInstanceLockoutInfo()` / `NIT.hourlyLimit`, same as the NIT minimap. NIT's own minimap text already walks the log **every 1s** (`NIT:ticker`). GoldTrack does not. We pull on dungeon enter/leave (`PLAYER_ENTERING_WORLD` + 0.5s + 2s so NIT can write `leftTime`) and once when a cached lock ages past 1 hour. Never faster than 1s. HUD 0.2s only paints the cache. Miss a count only if you delete/merge a NIT row without zoning (next zone or lock expiry fixes it).
- **G/h** large number (gold/hour, 1 decimal)
- **G/m** 4px above Start (left) + **Reset** 4px above Start (right)
- Full-width **Start** / **Pause** / **Resume** (AFK)

HUD `OnUpdate` always ticks (lockout countdown while stopped). Session clock is idle when not started.

Until `minGhSeconds` (default **30**), the G/h slot shows remaining seconds (`30s` … `1s`) instead of a rate. G/m stays `-`. Raw ratio after that; no EMA.

**Start/Pause** pauses and resumes the clock. It does not reset. **Reset** (left-click) archives the session into Total (if non-empty) and clears. **Reset right-click** clears the session **without** archiving it into Total — the session is discarded. Both ask to confirm.

---

## Main window

Tabs: **Total**, **Session**, **Loot**, **Config**.

Total / Session / Config rows are centered on a minus: `name - value`.

Loot: name filter (Enter applies, Esc clears focus), Hide 0, columns Item / Qty / Gold / Src. Coin method shows `G`. Manual overrides show `*` on Src. Click a row to edit (docks beside main). Tooltip has vendor / DE / AH raw / cut / deposit / sell rate / AH net / why.

Session health line: colored **TSM / Auctionator / NIT** yes/no plus muted sellrate.

---

## Slash

| Command | |
| --- | --- |
| `/gt` | Toggle main window |
| `/gt hud` | Show/hide HUD |
| `/gt start` / `/gt stop` | Session clock |
| `/gt reset` | Archive + clear (confirm) |
| `/gt config` | Config tab |
| `/gt version` | Print detected client, max level |
| `/gt reseteconomy` | Reset valuation thresholds to this client's defaults |
| `/gt refresh` | Re-read TSM sell rate / sold-per-day on **current** session rows (does not rewrite gold or method) |
| `/gt stripde` | Remove DE/prospect reagent rows from **current** session |
| `/gt selftest` | Valuation fixtures + TSM probe (`itemID 21877` netherweave) |
| `/gt debug` | Classifier trace in chat |

## Keybinds

Optional, under **Key Bindings → AddOns → GoldTrack** (no defaults set):

| Binding | |
| --- | --- |
| Toggle Main Window | same as `/gt` |
| Start / Pause Session | same as HUD Start/Pause |
| Toggle HUD | same as `/gt hud` |
| Reset Session (asks to confirm) | same as `/gt reset` |

---

## Valuation (loot-time, frozen)

Grey (quality 0): always vendor.

BoP / soulbound / quest bind (`bindType` 1 or 4): never AH. DE only if **this character can Disenchant** (`IsSpellKnown(13262)` / skill line Enchanting). Else vendor or NONE 0.

**Mat track:** not DE-able, and (`stackCount > 1` or recipe class 9). DE-ability beats stack size (stackable thrown weapons stay gear).

**Mats → AH** if `ahNet >= 3 × vendor` **or** `ahNet >= vendor + 1g`. If vendor is 0, ignore the 3× test; require only +1g.

**Gear (DE-able) → AH** if `ahNet >= vendor + 10g` **and** `ahNet >= de + 8g`. Else DE if `de >= vendor + 1g`. Else vendor.

AH net (`if_sold`, default): `ahRaw - floor(ahRaw × cut) - floor(deposit × (1 - p))`. `cut` is 5% on faction AHs, 15% on neutral (Goblin) AHs. Deposit = vendor × preset % (0 if vendor 0); neutral AHs charge 5× the faction deposit.

**Auction durations differ per client.** Both clients use the same deposit *percentages* (15 / 30 / 60% of vendor price) but with different durations, so the deposit preset is client-specific: Classic Era is **2h=15% / 8h=30% / 24h=60%** (24h is the longest and costs 60%); TBC is **12h=15% / 24h=30% / 48h=60%** (24h is the middle at 30%). The Config → Deposit preset dropdown lists only the current client's real durations. The **AH cut** setting switches between faction (5%) and neutral (15%) houses; neutral also multiplies the deposit by 5.

If TSM sell rate is **fallback** (unknown), mode is forced to `if_sold` so a 50% guess does not haircut payout.

Auctionator `GetVendorPrice*` is vendor **buy** — never used. Vendor = `select(11, GetItemInfo)` sell price.

TSM `Destroy` on ore is prospect, not DE. DE only for DE-able gear.

TSM `dbminbuyout` is discarded if `< 0.30 × dbmarket` (bait).

TBC item merge key: `itemID:enchant:suffix` (uniqueId ignored).

---

## Price sources (Config → Sources)

**Price source** (default **Atr &lt;2h else TSM**):

- Auctionator if last scan age is under 2 hours, else TSM (then Atr if TSM missing)
- TSM then Atr
- Atr then TSM
- TSM only
- Atr only

If Auctionator age cannot be read, Atr is treated as not-fresh.

**TSM price** (default Market):

- Market (`DBMarket` / `dbregionmarketavg`)
- Min buyout
- Recent
- Historical
- Region sale avg

That field is what TSM is asked for. Frozen at loot; changing config does not rewrite old rows.

Sell rate: `DBRegionSaleRate` (0 is valid). Auctionator has no sell-rate API.

`/gt refresh` updates sellRate / soldPerDay / source on current rows only. Also runs quietly at login (2s / 8s / 20s) and when opening Loot.

---

## Config defaults

The valuation gold thresholds are **per client** (see **Client profiles** above); the table below shows the TBC/Anniversary values. All numeric fields accept decimals (`8.5` or `8,5`).

| Key | Default (TBC) |
| --- | --- |
| Gear: AH beats vendor by | 10g |
| Gear: AH beats DE by | 8g |
| DE beats vendor by | 1g |
| Mats: AH >= vendor × | 3 |
| Mats: or vendor + | 1g |
| Min sell rate | 0.10 |
| Fallback sell rate | 0.50 |
| Subtract expected AH deposit | on |
| Deposit preset | 24h / 30% (TBC) — 8h / 30% (Era) |
| AH cut | Faction (5%) — neutral (15%) optional |
| AH value mode | If sold |
| Seconds before g/h | 30 |
| Pause clock while AFK | on |
| Resume after /reload | on (gap ≤ 60s) |
| Resume after logout | off |
| Count quest rewards | off |

All numeric fields accept decimals (`8.5` or `8,5`).

---

## Clock

Persisted: `activeMs`, `state`, `leavingAt`. **Never** persist `GetTime()` / `segmentStart`.

- `PLAYER_LEAVING_WORLD`: fold segment, set `leavingAt`
- `PLAYER_LOGOUT`: STOP unless resume-after-logout
- `/reload` within 60s + resume-after-reload: keep RUNNING
- `PLAYER_ENTERING_WORLD`: start segment; a `RUNNING` session started on a different character (`session.unit`) is stopped instead of resumed
- AFK: fold / resume segment (does not STOP)

---

## Loot classifier

World loot: `LOOT_ITEM_SELF` / `_MULTIPLE` always (even with vendor/AH open).

PUSHED only if loot-frame recency, gather spell, or (config) quest rewards + quest window.

Party coin: `LOOT_MONEY_SPLIT` without loot-frame. Also `YOU_LOOT_MONEY`.

Transfer lock (mail/trade/merchant/AH/bank/gbank/trainer/taxi/quest/tradeskill) does **not** suppress `LOOT_ITEM_SELF`.

OPEN (clams): pending queue; OPEN-suppress beats loot-frame. Bags 0–4 + keyring only.

DE/prospect: wire from `UNIT_SPELLCAST_SUCCEEDED` / `_START`, matching spellID **13262** / **31252** (and the localized name as a fallback). The handler accepts both the TBC Classic backport payload `(unit, castGUID, spellID, castBarID)` and the legacy `(unit, spellName, rank, lineID, spellID)` — it reads the spellID from the right argument, so DE reagent loot (dust/essence/shards/crystals) is ignored during the destroy window (5s, 10s from cast-start) or while the Enchanting trade skill is open. This stops DEing gear that was already in your bags (e.g. carried over a `/reload` or logout) from re-adding to gold/h. Mats often arrive as `You receive loot:`, not `You create:`.

If DE still leaked into the session: `/gt stripde` (current session only).

---

## Performance

- No combat-log parsing
- HUD pulse **off** when stopped (unless 5/5 red countdown). While running, 1s ticks (time is whole seconds). `SetText` skipped if unchanged.
- Loot / bag / spell / vendor events **unregistered** while the session is stopped
- Bag OnUpdate only while a bag flush or OPEN-pending is live
- NIT: zone + lock expiry only, never faster than NIT's 1s ticker
- `C_Timer.After` instead of throwaway OnUpdate frames
- Price cache: 256 entries, 30s TTL, wipe-on-full. TSM login refresh skipped if session empty
- Dedup: 200-slot ring, 5s
- Loot list: 14 recycled rows (FauxScroll)
- Session rows capped at 400 unique merge keys
- Archives: last 30 compact sessions (no full loot replay)

SavedVariables: `GoldTrackDB` (account) + `GoldTrackCharDB` (per character).
