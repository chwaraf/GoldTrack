# GoldTrack — Classic Era, TBC Anniversary & WoW: Forever

Session gold-per-hour tracker for **Classic Era (1.15.x)**, **TBC Anniversary (2.5.5 / 2.5.6)** and **WoW: Forever (1.60.x)**, from a single package. `## Interface: 20505, 20506, 11507, 11508, 11509, 16001`.

Copy the `GoldTrack` folder to the client's addons directory:

- TBC Anniversary: `World of Warcraft/_anniversary_/Interface/AddOns/GoldTrack`
- Classic Era: `World of Warcraft/_classic_era_/Interface/AddOns/GoldTrack`
- WoW: Forever: `World of Warcraft/_classic_beta_/Interface/AddOns/GoldTrack`

Forever is a **retail-engine** client, so it is loaded from `GoldTrack_Camelot.toc` (`camelot` is Forever's game-type token). That manifest is identical to the base one except that it also loads `Forever.lua`, which flags the rest of the addon. If the client ever falls back to the plain `GoldTrack.toc`, detection still works — the base manifest lists 16001 too.

The addon auto-detects which client it is running on (`Forever.lua` load flag first, then the interface number, then `WOW_PROJECT_ID`) and applies the right economy defaults for that client (see **Client profiles** below).

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

| | TBC / Anniversary | Classic Era | WoW: Forever |
| --- | --- | --- | --- |
| AH beats vendor by | 10g | 1g | 1g |
| AH beats DE by | 8g | 1g | 1g |
| DE beats vendor by | 1g | 10s | 10s |
| Mats: or vendor + | 1g | 10s | 1g |
| HUD min level | 70 (min-level hide on) | 1 (min-level hide off) | 1 (min-level hide off) |
| Max level | 70 | 60 | 60 |
| Auction durations | 12h / 24h / 48h | 2h / 8h / 24h | 12h / 24h / 48h |
| Deposit preset | 24h / 30% | 8h / 20% | 24h / 30% |

Forever gets **Era-scale thresholds** (its level cap is 60 and its prices are Classic-sized, so TBC's 10g gates would never fire) on top of the **retail engine's 12/24/48h auction ladder** — see **WoW: Forever** below for why that pairing is a deliberate, documented assumption rather than a guess.

`/gt version` prints the detected client and max level. Future clients (WotLK, Cata, Mists) are detected and default to keeping current values until tuned.

## WoW: Forever (1.60.x / "Camelot")

Forever is Blizzard's permanent Classic-line megaserver branch (beta 2026-09-17, full launch 2026-11-04). It is a **Classic game on the retail client**: level cap 60, Classic economy and Classic auction-house rules — but the **retail API surface**. That combination is what breaks Classic addons, so GoldTrack ports the API rather than guessing at it.

**Detection.** Forever reports `WOW_PROJECT_ID == WOW_PROJECT_MAINLINE`, i.e. it is *indistinguishable from retail by project id*, and its interface number (16001) is outside every Classic band. Checking `WOW_PROJECT_ID` first therefore mislabels it "retail", and an interface-number cascade mislabels it "era" (16001 ≥ 11500). `GT.DetectGameVersion()` resolves Forever **first**, from the load flag set by `Forever.lua` (which only `GoldTrack_Camelot.toc` lists) and from the 16000–19999 interface band, then falls back to the project-id/interface cascade for the Classic clients. Related trap for anyone reading this to port something else: `select(4, GetBuildInfo()) >= 100000` misreads 16001 as a Classic build.

**API layer (`Compat.lua`).** Every Classic-only global the addon used is resolved through `GT.Api`, which picks whichever implementation the client actually has:

| Used to be (Classic) | Forever (retail engine) | Where it mattered |
| --- | --- | --- |
| `GetItemInfo` | `C_Item.GetItemInfo` | `Prices.lua` captured it at file scope, so it was `nil` on Forever and crashed before `ADDON_LOADED` |
| `GetItemInfoInstant`, `GetItemCount` | `C_Item.*` | price probes, bag transforms |
| `GetSpellInfo` | `C_Spell.GetSpellName` / `C_Spell.GetSpellInfo` (returns a **table**, not positional values) | DE/prospect spell matching, open-trade-skill name |
| `IsAddOnLoaded`, `GetAddOnMetadata` | `C_AddOns.*` | Auctionator / TSM / NIT detection |
| `GetContainerItemInfo` | `C_Container.GetContainerItemInfo` (returns a **table**) | bag scans for OPEN/DE transforms |
| `GetNumSkillLines` / `GetSkillLineInfo` | **absent** — `GetProfessions` + `GetProfessionInfo` | Mining and Enchanting detection |
| `GetTradeSkillLine` | **absent** — `C_TradeSkillUI.GetBaseProfessionInfo` | "Enchanting window is open" suppression |

Professions are now asked for by **spell id** rather than by localized name: `GT.Api.KnowsProfession(2575)` for Mining and `(7411)` for Enchanting. That is what makes the automatic ore→bar valuation and the DE-suppression window work on a client that has no skill lines at all — and it stays correct on a non-English client, which the old name matching never was.

**Events throw.** On Forever, registering an event the client does not define is a hard Lua error, and that aborts the rest of the file — so one bad name silently kills every registration after it. Two real cases were latent in GoldTrack: `BAG_UPDATE` (removed in retail 10.0) was always registered because the guard tested `_G.BAG_UPDATE_DELAYED`, and event names are never globals; `LOOT_READY` was *never* registered because `if LOOT_READY then` tested a global that does not exist. `GT.Api.RegisterEvent()` pcall-wraps every registration and `GT.Events.SetListen()` attempts both bag events and `LOOT_READY`, so each client registers what it has and skips the rest. Boot events (`ADDON_LOADED`, `PLAYER_LOGIN`, `PLAYER_ENTERING_WORLD`, …) exist everywhere and are left direct.

**SavedVariables do not persist — yet.** The Forever beta writes SavedVariables on exit but does not read the **account-wide** table back (a client bug, independently confirmed by several authors during the beta); **per-character** tables do come back. GoldTrack's ledger is per-character (`GoldTrackCharDB`), so sessions, rows and archives are unaffected. Only the account-wide config would reset on every login, so on Forever — and only there — GoldTrack mirrors `GoldTrackDB` into `GoldTrackCharDB.__cfgMirror` and restores it when the account table arrives empty. Both directions are no-ops on other clients, and the restore self-disables the moment Blizzard fixes the bug (a correctly restored `GoldTrackDB` has `gameVersionKnown` set, which is the marker used to tell the two cases apart). A note is printed once per session. SavedVariables are also always **mutated in place** and never reassigned, including the `/gt wipe` path, because the client serializes the table it captured at load.

**Secret values are not used.** Forever hides combat values (damage, health, power) from addons, which is why damage meters and boss timers cannot work there. GoldTrack reads only chat loot, money strings, item info and profession/spell facts, so nothing it depends on is secret.

**Economy assumptions (beta stage).** Forever's auction-house fee table is not published. GoldTrack uses **Era-scale valuation thresholds** (level-60 Classic prices, so TBC's 10g gates would never fire) with the **retail engine's 12h/24h/48h duration ladder and TBC's 15/30/60% deposits**, which is what Forever's own guides describe (a 48-hour listing window, "the same deposit-vs-profit math as Classic"). If the real fee table differs, it is changed in **one place**: `GT.AH_PRESETS.forever` in `Version.lua`, which the presets, the default and the migration remap all read. `/gt reseteconomy` re-applies Forever's defaults after any such change.

**Tested how.** Both client families are booted from their actual TOC files under a Lua mock that reproduces Forever's environment — Classic globals absent, `C_Item`/`C_Spell`/`C_AddOns`/`C_Container`/`C_TradeSkillUI` present, `WOW_PROJECT_ID = 1`, interface 16001, and `RegisterEvent` **throwing** on unknown events so the pcall guard is genuinely exercised. Client detection, the AH ladder, profession checks, item resolution, the full ore→bar valuation (including the deferred `GET_ITEM_INFO_RECEIVED` upgrade), every window build and the SavedVariables mirror all produce **identical results** in both modes.

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

Loot: name filter (Enter applies, Esc clears focus), Hide 0, columns Item / Qty / Gold / Src. Coin method shows `G`. Manual overrides show `*` on Src. Click a row to edit (docks beside main). Tooltip has vendor / DE / AH raw / cut / deposit / sell rate / AH net / why. If the row is a **smeltable ore** the edit popup also shows a **Smelt** section with **To bar** (revalue at the bar's per-ore AH net) and **Vendor bar** (revalue at the bar's per-ore vendor price) — handy when you're going to smelt and either AH or vendor the bars rather than sell the ore raw.

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

**Mined ore → smelted bar.** If the player has **Mining** and the mat is a single-ore smelt (Copper/Tin/Silver/Iron/Gold/Mithril/Thorium/Truesilver ore), GoldTrack also values the **bar** produced from one ore and credits the ore at whichever is higher — the bar's own disposition (AH net or vendor) per ore is compared against the raw ore's. So if a server posts Copper Bar above Copper Ore, looting ore is counted at the bar's value; if the bar just vendors for more, that's counted too. (Multi-reagent alloys like Bronze/Steel/Felsteel are not treated this way — they're not a clean one-ore→one-bar choice.)

This runs in the **automatic** valuation, not just the manual Loot-popup buttons — an ore row lands at the bar's value on its own, with no clicking. Two things make that reliable, because item info (`GetItemInfo()` on Classic, `C_Item.GetItemInfo()` on Forever) is asynchronous and the bar is usually *not* known to the client at the moment the ore drops:

- **Prefetch at login.** Miners get every smelt bar's item data requested at `PLAYER_LOGIN` (retried at +2s and +20s, alongside the TSM passes, since skill lines and the item cache are not always ready immediately). So by the time you loot ore, the bar resolves and the comparison happens at loot time — the row's value is correct from the start and freeze-at-loot is preserved.
- **Deferred re-check.** If the comparison still could not be completed (bar item data missing, or the bar loaded but no AH market data for it yet), the row is flagged `smeltPending` and re-checked when that data arrives — on `GET_ITEM_INFO_RECEIVED` for a smelt bar, and on the price-refresh passes. The re-check only ever **raises** a value (`SmeltBetter` returns nothing unless the bar is strictly worth more), never touches a **manual override**, and stops retrying a row as soon as the verdict becomes final (bar priced and simply not better). Once decided, a row is never revisited, so ordinary frozen rows are unaffected by later price movement.

The manual **To bar** / **Vendor bar** buttons remain available for forcing a disposition the automatic rule would not pick (e.g. the bar's AH value when the rule engine prefers vendor).

**Gear (DE-able) → AH** if `ahNet >= vendor + 10g` **and** `ahNet >= de + 8g`. Else DE if `de >= vendor + 1g`. Else vendor.

AH net (`if_sold`, default): `ahRaw - floor(ahRaw × cut) - floor(deposit × (1 - p))`. `cut` is 5% on faction AHs, 15% on neutral (Goblin) AHs. Deposit = vendor × preset % (0 if vendor 0); neutral AHs charge 5× the faction deposit.

**Auction durations and deposit percentages differ per client.** The durations are *different* and so are the deposit percentages: Classic Era (pre-2.3/Vanilla) is **2h=5% / 8h=20% / 24h=60%** (a 24h listing is the longest and costs 60%); TBC and Forever (post-2.3 ladder) are **12h=15% / 24h=30% / 48h=60%** (24h is the middle at 30%). The Config → Deposit preset dropdown lists only the current client's real durations and percentages. The **AH cut** setting switches between faction (5%) and neutral (15%) houses; neutral also multiplies the deposit by 5.

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
| Deposit preset | 24h / 30% (TBC & Forever) — 8h / 20% (Era) |
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
