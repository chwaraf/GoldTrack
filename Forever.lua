--[[ GoldTrack — load-time WoW: Forever marker.

This file is listed ONLY in GoldTrack_Camelot.toc. "Camelot" is Blizzard's
internal game-type token for World of Warcraft: Forever, and the Forever client
is the one that reads a _Camelot manifest (the way Classic Era reads _Vanilla
and Retail reads _Mainline). So if this chunk ran, we are on Forever — a signal
that cannot be produced on any other client.

Why a load-time flag at all, when Version.lua also detects Forever by interface
number: at runtime Forever is indistinguishable from live Retail by project id
(WOW_PROJECT_ID == WOW_PROJECT_MAINLINE on both), so the interface number is the
only runtime discriminator, and it is a band (16000-19999) rather than an exact
value. A load-time marker is authoritative and costs one boolean, so detection
uses it first and the interface band as the fallback for a plain GoldTrack.toc
install (a multi-interface manifest is enough for the client to load the addon;
the _Camelot manifest is what makes this flag reliable).

Ordered after Core.lua, which creates the GoldTrack table, and before
Version.lua, which reads the flag.
]]
local GT = GoldTrack

GT.isForeverTOC = true
