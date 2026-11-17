--[[
    Hand-me-downs: things one character is holding that another could use.

      Gear      - not soulbound, the other character's class wears it, it's an upgrade on what they
                  have on now (item level, or an empty slot), and they can use it now or within a
                  few levels.
      Materials - trade goods for the other character's main professions (Leatherworking,
                  Tailoring...; not Cooking, Fishing or First Aid), when the holder has no use
                  for them in their own professions.

    Clicking a suggestion puts it on Family Mailbox's post list for that character.
]]

local FM = FamilyMailbox

-- how many levels ahead gear may be ("ready at 18")
FM.HAND_LEVELS_AHEAD = 3

---------------------------------------------------------------------------
-- Item facts (cached; GetItemInfo can need the server the first time)
---------------------------------------------------------------------------
local info, waiting = {}, {}

local function Info(id)
    local i = info[id]
    if i then return i end
    local itemType, equipLoc, classID, subclassID
    if C_Item and C_Item.GetItemInfoInstant then
        local _, _, _, loc, _, cls, sub = C_Item.GetItemInfoInstant(id)
        equipLoc, classID, subclassID = loc, cls, sub
    end
    local name, link, quality, ilvl, minLevel, _, _, _, loc2, _, _, cls2, sub2, bindType
    if C_Item and C_Item.GetItemInfo then
        name, link, quality, ilvl, minLevel, _, _, _, loc2, _, _, cls2, sub2, bindType = C_Item.GetItemInfo(id)
    end
    if not name then
        -- not in the cache yet: ask, and look again when it arrives
        waiting[id] = true
        if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
        return nil
    end
    if C_Item and C_Item.GetDetailedItemLevelInfo and link then
        local ok, eff = pcall(C_Item.GetDetailedItemLevelInfo, link)
        if ok and eff then ilvl = eff end
    end
    i = { name = name, link = link, quality = quality or 1, ilvl = ilvl or 0, minLevel = minLevel or 0,
          equipLoc = equipLoc or loc2 or "", classID = classID or cls2, subclassID = subclassID or sub2,
          bindType = bindType or 0 }
    info[id] = i
    return i
end
FM.HandInfo = Info

function FM.HandItemArrived(id)
    if id and waiting[id] then
        waiting[id] = nil
        if not FM.handRefreshQueued then
            FM.handRefreshQueued = true
            C_Timer.After(0.5, function()
                FM.handRefreshQueued = false
                if FM.UI and FM.UI.Refresh then FM.UI.Refresh() end
            end)
        end
    end
end

local function StatsOf(link)
    local get = (C_Item and C_Item.GetItemStats) or GetItemStats
    if not (get and link) then return nil end
    local ok, t = pcall(get, link)
    return ok and type(t) == "table" and t or nil
end

---------------------------------------------------------------------------
-- Who wears what (Classic rules)
---------------------------------------------------------------------------
local ARMOR, WEAPON, MISC = 4, 2, 0
local CLOTH, LEATHER, MAIL, PLATE, SHIELD = 1, 2, 3, 4, 6

-- the armour each class should be wearing (mail and plate from 40 for those who learn them)
local function ArmorFor(class, level)
    level = level or 1
    if class == "WARRIOR" or class == "PALADIN" then return level >= 40 and PLATE or MAIL end
    if class == "HUNTER" or class == "SHAMAN" then return level >= 40 and MAIL or LEATHER end
    if class == "ROGUE" or class == "DRUID" then return LEATHER end
    return CLOTH -- mage, priest, warlock
end

-- weapon subclasses: 0 1h axe, 1 2h axe, 2 bow, 3 gun, 4 1h mace, 5 2h mace, 6 polearm, 7 1h sword,
-- 8 2h sword, 10 staff, 13 fist, 15 dagger, 16 thrown, 18 crossbow, 19 wand
local WEAPONS = {
    WARRIOR = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18 },
    PALADIN = { 0, 1, 4, 5, 6, 7, 8 },
    HUNTER  = { 0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18 },
    ROGUE   = { 2, 3, 4, 7, 13, 15, 16, 18 },
    PRIEST  = { 4, 10, 15, 19 },
    SHAMAN  = { 0, 1, 4, 5, 10, 13, 15 },
    MAGE    = { 7, 10, 15, 19 },
    WARLOCK = { 7, 10, 15, 19 },
    DRUID   = { 4, 5, 10, 13, 15 },
}
local SHIELDS = { WARRIOR = true, PALADIN = true, SHAMAN = true }
local OFFHANDS = { PRIEST = true, MAGE = true, WARLOCK = true, DRUID = true, SHAMAN = true, PALADIN = true }
local DUAL = { WARRIOR = true, ROGUE = true, HUNTER = true }

-- main stats each class wants (stamina suits everyone, so it never rules an item out)
local WANTS = {
    WARRIOR = { "STRENGTH", "AGILITY" }, PALADIN = { "STRENGTH", "INTELLECT" },
    HUNTER = { "AGILITY", "INTELLECT" }, ROGUE = { "AGILITY", "STRENGTH" },
    PRIEST = { "INTELLECT", "SPIRIT" }, SHAMAN = { "INTELLECT", "STRENGTH", "AGILITY" },
    MAGE = { "INTELLECT", "SPIRIT" }, WARLOCK = { "INTELLECT", "SPIRIT" },
    DRUID = { "INTELLECT", "AGILITY", "STRENGTH", "SPIRIT" },
}
local MAIN_STATS = { "STRENGTH", "AGILITY", "INTELLECT", "SPIRIT" }

-- equip slot(s) for each item kind
local SLOTS = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 },
    INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
    INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 },
    INVTYPE_WEAPON = { 16 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
    INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 },
    INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}
local SLOT_NAME = { "Head", "Neck", "Shoulders", nil, "Chest", "Waist", "Legs", "Feet", "Wrists", "Hands",
    "Ring", "Ring", "Trinket", "Trinket", "Back", "Main hand", "Off hand", "Ranged" }

local function Has(list, v) for _, x in ipairs(list or {}) do if x == v then return true end end end

-- can this class use this item at all, and is it the right kind for them?
function FM.HandWears(class, level, i)
    if not (class and i) then return false end
    local loc = i.equipLoc
    if loc == "INVTYPE_WEAPONOFFHAND" and not DUAL[class] then return false end
    if loc == "INVTYPE_HOLDABLE" then return OFFHANDS[class] == true end
    if i.classID == ARMOR then
        if i.subclassID == SHIELD then return SHIELDS[class] == true end
        if i.subclassID == MISC or loc == "INVTYPE_CLOAK" then return true end -- rings, necks, trinkets, cloaks
        if loc == "INVTYPE_RELIC" then return false end
        return i.subclassID == ArmorFor(class, level)
    elseif i.classID == WEAPON then
        return Has(WEAPONS[class], i.subclassID)
    end
    return false
end

-- does it have the right stats for them (no Intellect plate for a warrior)?
function FM.HandStatsFit(class, link)
    local stats = StatsOf(link)
    if not stats then return true end
    local hasMain, fits = false, false
    for _, s in ipairs(MAIN_STATS) do
        local key = "ITEM_MOD_" .. s .. "_SHORT"
        if (stats[key] or 0) > 0 then
            hasMain = true
            if Has(WANTS[class], s) then fits = true end
        end
    end
    return fits or not hasMain
end

-- what they wear now, by slot: { [slot] = { id, ilvl } } (worked out from the worn item list)
function FM.HandWorn(c)
    local worn = {}
    local ring, trinket = {}, {}
    for id in pairs(c.equipped or {}) do
        local i = Info(id)
        local slots = i and SLOTS[i.equipLoc]
        if slots then
            local entry = { id = id, ilvl = i.ilvl }
            if i.equipLoc == "INVTYPE_FINGER" then ring[#ring + 1] = entry
            elseif i.equipLoc == "INVTYPE_TRINKET" then trinket[#trinket + 1] = entry
            elseif i.equipLoc == "INVTYPE_WEAPON" and worn[16] then worn[17] = entry
            else
                worn[slots[1]] = entry
                if i.equipLoc == "INVTYPE_2HWEAPON" then worn.twoHand = true end
            end
        end
    end
    table.sort(ring, function(a, b) return a.ilvl > b.ilvl end)
    table.sort(trinket, function(a, b) return a.ilvl > b.ilvl end)
    worn[11], worn[12], worn[13], worn[14] = ring[1], ring[2], trinket[1], trinket[2]
    return worn
end

-- is item `i` better than what `c` has on? returns the slot and what it replaces
function FM.HandUpgrade(c, i)
    local slots = SLOTS[i.equipLoc]
    if not slots then return nil end
    local worn = FM.HandWorn(c)
    local bestSlot, against
    for _, slot in ipairs(slots) do
        local cur = worn[slot]
        if slot == 17 and worn.twoHand then cur = { ilvl = math.huge } end -- a two-hander leaves no off hand
        if not cur then return slot, nil end
        if not against or cur.ilvl < against.ilvl then bestSlot, against = slot, cur end
    end
    if i.equipLoc == "INVTYPE_2HWEAPON" and worn[17] then
        -- swapping a weapon and off hand for one two-hander: it has to beat the main hand
        against = worn[16] or against
    end
    if against and i.ilvl > against.ilvl then return bestSlot, against end
    return nil
end

---------------------------------------------------------------------------
-- Materials: trade goods -> the professions that use them
---------------------------------------------------------------------------
local TRADEGOODS = 7
local ALCH, BS, ENCH, ENG, LW, TAIL, JC, INSC = 171, 164, 333, 202, 165, 197, 755, 773
FM.HAND_CRAFTS = { [ALCH] = true, [BS] = true, [ENCH] = true, [ENG] = true, [LW] = true, [TAIL] = true, [JC] = true, [INSC] = true }
local USED_BY = {
    [1] = { ENG }, [2] = { ENG }, [3] = { ENG },        -- parts, explosives, devices
    [4] = { JC },                                       -- jewelcrafting (gems)
    [5] = { TAIL },                                     -- cloth
    [6] = { LW },                                       -- leather and hides
    [7] = { BS, ENG, JC },                              -- metal and stone
    [9] = { ALCH, INSC },                               -- herbs
    [10] = { ALCH, BS, LW, TAIL, ENCH, ENG },           -- elemental
    [12] = { ENCH },                                    -- dusts, essences, shards
    [16] = { INSC },                                    -- inks, pigments
}

-- the crafting professions of a character that use this material (Cooking, Fishing, First Aid
-- and the gathering ones never count)
function FM.HandCraftsFor(c, i)
    local out = {}
    if not (i and i.classID == TRADEGOODS) then return out end
    local users = USED_BY[i.subclassID]
    if not users then return out end
    for _, p in ipairs(c.profs or {}) do
        if p.line and FM.HAND_CRAFTS[p.line] and Has(users, p.line) then out[#out + 1] = p end
    end
    return out
end

---------------------------------------------------------------------------
-- Suggestions
---------------------------------------------------------------------------
local LOCS = { "bags", "bank", "mail" }

local function Bound(holder, loc, id, i)
    local set = holder[loc .. "Bound"]
    if set and set[id] then return true end
    -- nothing recorded for this place (e.g. Syndicator data): bind-on-pickup and quest items are bound
    if not set and loc ~= "mail" and (i.bindType == 1 or i.bindType == 4) then return true end
    return false
end

-- every suggestion, best first. Each: { id, recipient, holder, loc, count, kind = "gear"|"mat", text, score }
-- onlyRecipient / onlyHolder narrow it down.
function FM.HandMeDowns(onlyRecipient, onlyHolder)
    local db = FM.DB()
    local out = {}
    local keys = FM.Characters()
    local group = {}
    for _, k in ipairs(keys) do group[k] = db.chars[k] end
    local myRealm = db.chars[FM.MyKey()] and db.chars[FM.MyKey()].realm

    for _, hk in ipairs(keys) do
        local holder = db.chars[hk]
        if (not onlyHolder or onlyHolder == hk) and holder.realm == myRealm then
            for _, loc in ipairs(LOCS) do
                for id, count in pairs(holder[loc] or {}) do
                    local i = Info(id)
                    if i and not Bound(holder, loc, id, i) then
                        for _, rk in ipairs(keys) do
                            local r = db.chars[rk]
                            if rk ~= hk and (not onlyRecipient or onlyRecipient == rk) and r.realm == holder.realm
                                and (not r.faction or not holder.faction or r.faction == holder.faction) then
                                -- gear
                                if (i.classID == ARMOR or i.classID == WEAPON) and i.quality >= 1 and r.class and r.level
                                    and FM.HandWears(r.class, r.level, i) and FM.HandStatsFit(r.class, i.link) then
                                    local lvl = r.level or 1
                                    if i.minLevel <= lvl + FM.HAND_LEVELS_AHEAD then
                                        local slot, against = FM.HandUpgrade(r, i)
                                        if slot then
                                            local was = against and ("item level " .. i.ilvl .. " vs " .. against.ilvl
                                                .. " (" .. FM.ItemName(against.id) .. ")") or "nothing worn there"
                                            local when = i.minLevel > lvl and ("  - ready at level " .. i.minLevel) or ""
                                            out[#out + 1] = { id = id, recipient = rk, holder = hk, loc = loc, count = count,
                                                kind = "gear", slot = slot,
                                                text = (SLOT_NAME[slot] or "Gear") .. " upgrade: " .. was .. when,
                                                score = 1000 + (i.ilvl - (against and against.ilvl or 0)) - (i.minLevel > lvl and 500 or 0) }
                                        end
                                    end
                                end
                                -- materials: useful to the recipient, no use to the holder
                                local crafts = FM.HandCraftsFor(r, i)
                                if #crafts > 0 and #FM.HandCraftsFor(holder, i) == 0 then
                                    local p = crafts[1]
                                    local skill = (p.rank and p.max) and (" (" .. p.rank .. "/" .. p.max .. ")") or ""
                                    out[#out + 1] = { id = id, recipient = rk, holder = hk, loc = loc, count = count,
                                        kind = "mat", text = "For " .. p.name .. skill, score = 100 + math.min(count, 99) }
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    -- gear: keep only the best suggestion per recipient and slot
    local best = {}
    for _, s in ipairs(out) do
        if s.kind == "gear" then
            local k = s.recipient .. ":" .. s.slot
            if not best[k] or s.score > best[k].score then best[k] = s end
        end
    end
    local final = {}
    for _, s in ipairs(out) do
        if s.kind ~= "gear" or best[s.recipient .. ":" .. s.slot] == s then final[#final + 1] = s end
    end
    table.sort(final, function(a, b)
        if a.recipient ~= b.recipient then return a.recipient < b.recipient end
        if a.kind ~= b.kind then return a.kind == "gear" end
        if a.score ~= b.score then return a.score > b.score end
        return a.id < b.id
    end)
    return final
end

-- a line in chat when you log in on someone holding hand-me-downs
function FM.HandLoginNote()
    if not FM.DB().settings.handNote then return end
    local list = FM.HandMeDowns(nil, FM.MyKey())
    if #list == 0 then return end
    local who = {}
    for _, s in ipairs(list) do who[FM.DB().chars[s.recipient].name] = true end
    local names = {}
    for n in pairs(who) do names[#names + 1] = n end
    table.sort(names)
    FM.Print(("%d hand-me-down%s here for %s. Type |cffffd100/fm hand|r to see them."):format(
        #list, #list == 1 and "" or "s", table.concat(names, ", ")))
end
