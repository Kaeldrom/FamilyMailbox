--[[
    Family Mailbox
    Remembers what every character on the account is carrying (bags, bank,
    mailbox, worn gear and gold), shows it in one searchable window and on
    item tooltips, and helps post things from one character to another.

    Data lives in the account-wide SavedVariables table FamilyMailboxDB:
      chars[Name-Realm] = { name, realm, class, faction, level, money, mailMoney,
                            bags = {[itemID]=n}, bank = {...}, mail = {...}, equipped = {...},
                            updated, bankSeen, mailSeen }
      items[itemID]     = last item link seen (for names, colours and tooltips)
      queue[Name-Realm] = { [itemID] = true }   -- "post this to that character"
]]

local ADDON = ...
local FM = {}
FamilyMailbox = FM

FM.LOCATIONS = { "bags", "bank", "mail", "equipped" }
FM.LOCATION_LABEL = { bags = "bags", bank = "bank", mail = "mail", equipped = "worn" }

local DEFAULT_SETTINGS = { tooltip = true, mailPanel = true }

local db, me, myKey
local bankOpen = false

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffd100Family Mailbox|r: " .. tostring(msg))
end
FM.Print = Print

local function IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v)
end

---------------------------------------------------------------------------
-- Names
---------------------------------------------------------------------------
local function NormRealm(r)
    return ((r or ""):gsub("[%s%-']", ""))
end

-- WoW Forever has no realms: names are unique per region and every character has
-- a surname ("Gromir Crypmaghar"). Characters are grouped by ruleset (PvP, PvE...)
-- instead, and mail is addressed to the full name.
local function Regional()
    return RegionalUniqueNamesEnabled ~= nil and RegionalUniqueNamesEnabled() == true
end

local function Ruleset()
    local G = C_GameRules
    local R = Enum and Enum.GameRule
    if not (G and G.IsGameRuleActive and R) then return "Regional" end
    local function On(rule) return rule ~= nil and G.IsGameRuleActive(rule) end
    if On(R.HardcoreRuleset) then return "HC" end
    if On(R.PvPRuleset) and On(R.RPRuleset) then return "RPPvP" end
    if On(R.PvPRuleset) then return "PvP" end
    if On(R.RPRuleset) then return "RP" end
    return "PvE"
end

local function SurnameSep()
    local c = Constants and Constants.CharacterNameSeparatorConsts
    return (c and c.CHARACTERNAME_SURNAME_SEPARATOR) or " "
end

local myGroup

local function MyRealm()
    if myGroup then return myGroup end
    local r = GetNormalizedRealmName and GetNormalizedRealmName()
    if not r or r == "" then r = NormRealm(GetRealmName and GetRealmName()) end
    return r
end

function FM.Key(name, realm)
    return name .. "-" .. NormRealm(realm or MyRealm())
end

-- who am I? first name, full (mail) name, group (realm or ruleset), key
function FM.Identity()
    if Regional() then
        local first, surname = (UnitNameUnmodified or UnitName)("player")
        local full = (surname and surname ~= "") and (first .. SurnameSep() .. surname) or first
        local group = Ruleset()
        return first, full, group, full .. "-" .. group
    end
    local name, realm = UnitFullName("player")
    if not realm or realm == "" then realm = MyRealm() end
    return name, name, realm, FM.Key(name, realm)
end

function FM.FullName(c) return c.full or c.name end

-- "Gromir Crypmaghar", "gromir", "Tahu-Realm" -> key of a known character in my group, or nil
function FM.FindCharacter(text)
    if not text or text == "" or IsSecret(text) then return nil end
    local name, realm = text:match("^(.-)%-([^%-]+)$")
    name = (name or text):lower()
    realm = NormRealm(realm or MyRealm()):lower()
    local byFirst, firstCount
    for key, c in pairs(db.chars) do
        if NormRealm(c.realm):lower() == realm then
            if FM.FullName(c):lower() == name then return key end
            if c.name:lower() == name then byFirst, firstCount = key, (firstCount or 0) + 1 end
        end
    end
    if firstCount == 1 then return byFirst end
end

function FM.MyKey() return myKey end
function FM.DB() return db end

---------------------------------------------------------------------------
-- Items
---------------------------------------------------------------------------
local function Remember(id, link)
    if id and link and not IsSecret(link) then db.items[id] = link end
end

function FM.ItemLink(id)
    local link = db.items[id]
    if not link and C_Item and C_Item.GetItemInfo then
        link = select(2, C_Item.GetItemInfo(id))
        if link then db.items[id] = link end
    end
    return link
end

function FM.ItemName(id)
    local link = FM.ItemLink(id)
    local name = link and link:match("|h%[(.-)%]|h")
    if not name and C_Item and C_Item.GetItemInfo then name = C_Item.GetItemInfo(id) end
    return name or ("item:" .. id)
end

function FM.ItemIcon(id)
    if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(id) end
    return GetItemIcon and GetItemIcon(id)
end

---------------------------------------------------------------------------
-- Scanning this character
---------------------------------------------------------------------------
local BAG_IDS, BANK_IDS = {}, {}

local function BuildBagLists()
    local E = (Enum and Enum.BagIndex) or {}
    BAG_IDS = {}
    for b = 0, (NUM_BAG_SLOTS or 4) do BAG_IDS[#BAG_IDS + 1] = b end
    if E.ReagentBag then BAG_IDS[#BAG_IDS + 1] = E.ReagentBag end
    if E.Keyring then BAG_IDS[#BAG_IDS + 1] = E.Keyring end

    BANK_IDS = {}
    if E.CharacterBankTab_1 then
        -- modern client: the bank is up to nine purchasable tabs
        for i = 1, 12 do
            local id = E["CharacterBankTab_" .. i]
            if id then BANK_IDS[#BANK_IDS + 1] = id end
        end
    else
        -- classic layout: the bank itself plus bank bag slots
        BANK_IDS[1] = E.Bank or -1
        local first = (NUM_BAG_SLOTS or 4) + 1
        for i = 0, (NUM_BANKBAGSLOTS or 7) - 1 do BANK_IDS[#BANK_IDS + 1] = first + i end
    end
end

local function IsIn(list, v)
    for _, x in ipairs(list) do if x == v then return true end end
end

-- returns counts {[itemID]=n} and the number of slots looked at
local function ScanContainers(ids)
    local counts, slots = {}, 0
    for _, bag in ipairs(ids) do
        local n = C_Container.GetContainerNumSlots(bag) or 0
        slots = slots + n
        for slot = 1, n do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID and not IsSecret(info.itemID) then
                counts[info.itemID] = (counts[info.itemID] or 0) + (info.stackCount or 1)
                Remember(info.itemID, info.hyperlink)
            end
        end
    end
    return counts, slots
end

local scan = {}

function scan.bags()
    me.bags = ScanContainers(BAG_IDS)
end

local bankRetried = false
function scan.bank()
    if not bankOpen then return end
    local counts, slots = ScanContainers(BANK_IDS)
    if slots == 0 and not bankRetried then
        -- bank tabs can take a moment to arrive; don't wipe what we knew
        bankRetried = true
        C_Timer.After(1, function() FM.Dirty("bank") end)
        return
    end
    me.bank = counts
    me.bankSeen = time()
end

function scan.mail()
    local counts, money = {}, 0
    local maxAttach = ATTACHMENTS_MAX_RECEIVE or ATTACHMENTS_MAX or 16
    for i = 1, (GetInboxNumItems() or 0) do
        local _, _, _, _, gold, cod = GetInboxHeaderInfo(i)
        if gold and not IsSecret(gold) and (not cod or cod == 0) then money = money + gold end
        for a = 1, maxAttach do
            local _, id, _, count = GetInboxItem(i, a)
            if id and not IsSecret(id) then
                counts[id] = (counts[id] or 0) + (count or 1)
                Remember(id, GetInboxItemLink(i, a))
            end
        end
    end
    me.mail = counts
    me.mailMoney = money
    me.mailSeen = time()
end

function scan.equipped()
    local counts = {}
    for slot = 0, 19 do
        local id = GetInventoryItemID("player", slot)
        if id and not IsSecret(id) then
            -- slot 0 is the ammo slot on older rulesets: count the whole stack
            local n = 1
            if slot == 0 and GetInventoryItemCount then n = GetInventoryItemCount("player", slot) or 1 end
            counts[id] = (counts[id] or 0) + n
            Remember(id, GetInventoryItemLink("player", slot))
        end
    end
    me.equipped = counts
end

function scan.info()
    local _, class = UnitClass("player")
    me.class = class
    me.faction = UnitFactionGroup("player")
    me.level = UnitLevel("player")
    me.money = GetMoney()
    -- the contents can only be read at a mailbox, but "is anything waiting?" works anywhere
    if HasNewMail then me.unreadMail = HasNewMail() and true or false end
end

local pending, flushQueued = {}, false

local function Flush()
    flushQueued = false
    for what in pairs(pending) do
        pending[what] = nil
        scan[what]()
    end
    me.updated = time()
    if FM.UI and FM.UI.Refresh then FM.UI.Refresh() end
end

function FM.Dirty(what)
    pending[what] = true
    if not flushQueued then
        flushQueued = true
        C_Timer.After(0.3, Flush)
    end
end
FM.Flush = Flush -- tests

---------------------------------------------------------------------------
-- Questions about the family
---------------------------------------------------------------------------
-- sorted list of keys: this realm first, then by name
function FM.Characters()
    local list, here = {}, MyRealm()
    for key in pairs(db.chars) do list[#list + 1] = key end
    table.sort(list, function(a, b)
        local ca, cb = db.chars[a], db.chars[b]
        local ha, hb = NormRealm(ca.realm) == here, NormRealm(cb.realm) == here
        if ha ~= hb then return ha end
        if ca.realm ~= cb.realm then return ca.realm < cb.realm end
        return ca.name < cb.name
    end)
    return list
end

-- family on this realm, not counting the character you're on
function FM.Postable()
    local list, here = {}, MyRealm()
    for _, key in ipairs(FM.Characters()) do
        if key ~= myKey and NormRealm(db.chars[key].realm) == here then list[#list + 1] = key end
    end
    return list
end

-- onlyLoc ("bags", "bank", "mail", "equipped") counts just that place
function FM.Count(key, id, onlyLoc)
    local c, total, where = db.chars[key], 0, {}
    for _, loc in ipairs(FM.LOCATIONS) do
        local n = (not onlyLoc or onlyLoc == loc) and c[loc] and c[loc][id] or 0
        where[loc] = n
        total = total + n
    end
    return total, where
end

-- "bags 2, bank 5"
function FM.WhereText(where)
    local parts = {}
    for _, loc in ipairs(FM.LOCATIONS) do
        if (where[loc] or 0) > 0 then parts[#parts + 1] = FM.LOCATION_LABEL[loc] .. " " .. where[loc] end
    end
    return table.concat(parts, ", ")
end

-- Search everything. onlyKey limits to one character, onlyLoc to one place.
-- Returns a sorted list of { id, name, total, holders = { {key, total, where}, ... } }
function FM.Search(text, onlyKey, onlyLoc)
    text = (text or ""):lower()
    local ids = {}
    for key, c in pairs(db.chars) do
        if not onlyKey or onlyKey == key then
            for _, loc in ipairs(FM.LOCATIONS) do
                if not onlyLoc or onlyLoc == loc then
                    for id in pairs(c[loc] or {}) do ids[id] = true end
                end
            end
        end
    end
    local results = {}
    for id in pairs(ids) do
        local name = FM.ItemName(id)
        if text == "" or name:lower():find(text, 1, true) then
            local r = { id = id, name = name, total = 0, holders = {} }
            for _, key in ipairs(FM.Characters()) do
                if not onlyKey or onlyKey == key then
                    local n, where = FM.Count(key, id, onlyLoc)
                    if n > 0 then
                        r.total = r.total + n
                        r.holders[#r.holders + 1] = { key = key, total = n, where = where }
                    end
                end
            end
            if r.total > 0 then results[#results + 1] = r end
        end
    end
    table.sort(results, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.id < b.id
    end)
    return results
end

function FM.TotalMoney()
    local sum = 0
    for _, c in pairs(db.chars) do sum = sum + (c.money or 0) + (c.mailMoney or 0) end
    return sum
end

-- Tooltip lines for an item: nothing if only this character's bags have it
function FM.TooltipLines(id)
    local lines, total, interesting = {}, 0, false
    for _, key in ipairs(FM.Characters()) do
        local n, where = FM.Count(key, id)
        if n > 0 then
            total = total + n
            if key ~= myKey or n ~= where.bags then interesting = true end
            lines[#lines + 1] = { db.chars[key].name, FM.WhereText(where), key }
        end
    end
    if not interesting then return {} end
    table.insert(lines, 1, { "Family has " .. total, "", nil })
    return lines
end

---------------------------------------------------------------------------
-- Post queue
---------------------------------------------------------------------------
function FM.IsQueued(key, id) return db.queue[key] ~= nil and db.queue[key][id] == true end

function FM.ToggleQueue(key, id)
    db.queue[key] = db.queue[key] or {}
    if db.queue[key][id] then db.queue[key][id] = nil else db.queue[key][id] = true end
    if next(db.queue[key]) == nil then db.queue[key] = nil end
    if FM.UI and FM.UI.Refresh then FM.UI.Refresh() end
end

function FM.QueueCount(key)
    local n = 0
    for _ in pairs(db.queue[key] or {}) do n = n + 1 end
    return n
end

-- stacks in my bags that are queued for `key`; bound ones are listed separately
function FM.QueuedInBags(key)
    local ok, bound = {}, {}
    local q = db.queue[key]
    if not q then return ok, bound end
    for _, bag in ipairs(BAG_IDS) do
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID and q[info.itemID] then
                local s = { bag = bag, slot = slot, id = info.itemID }
                if info.isBound then bound[#bound + 1] = s
                elseif not info.isLocked then ok[#ok + 1] = s end
            end
        end
    end
    return ok, bound
end

-- Called from a click at the mailbox: switch to Send Mail, address it to `key`
-- and attach whatever is queued for them. The player still presses Send.
function FM.PrepareMail(key)
    local c = db.chars[key]
    if not c then return 0, 0, 0 end
    if MailFrameTab_OnClick then pcall(MailFrameTab_OnClick, nil, 2) end
    if SendMailNameEditBox then
        local to = FM.FullName(c)
        if not Regional() and NormRealm(c.realm) ~= MyRealm() then to = to .. "-" .. c.realm end
        SendMailNameEditBox:SetText(to)
    end

    local stacks, bound = FM.QueuedInBags(key)
    local max = ATTACHMENTS_MAX_SEND or 12
    local used = {}
    for i = 1, max do if GetSendMailItem(i) then used[i] = true end end
    local attached, left = 0, 0
    ClearCursor()
    for _, s in ipairs(stacks) do
        local free
        for i = 1, max do if not used[i] then free = i break end end
        if free then
            used[free] = true
            C_Container.PickupContainerItem(s.bag, s.slot)
            ClickSendMailItemButton(free)
            attached = attached + 1
        else
            left = left + 1
        end
    end
    ClearCursor()
    if SendMailSubjectEditBox and attached > 0 and (SendMailSubjectEditBox:GetText() or "") == "" then
        SendMailSubjectEditBox:SetText("From " .. me.name)
    end
    return attached, left, #bound
end

---------------------------------------------------------------------------
-- Following mail we send to family, so it shows up before they log in
---------------------------------------------------------------------------
local outgoing

local function OnSendMail(recipient)
    outgoing = nil
    if IsSecret(recipient) then return end
    local key = FM.FindCharacter(recipient)
    if not key or key == myKey then return end
    local items = {}
    for i = 1, (ATTACHMENTS_MAX_SEND or 12) do
        local _, id, _, count = GetSendMailItem(i)
        if id then
            items[#items + 1] = { id = id, count = count or 1 }
            Remember(id, GetSendMailItemLink and GetSendMailItemLink(i))
        end
    end
    local money = GetSendMailMoney and GetSendMailMoney() or 0
    if #items > 0 or money > 0 then outgoing = { key = key, items = items, money = money } end
end

local function OnMailSent()
    if not outgoing then return end
    local c = db.chars[outgoing.key]
    c.mail = c.mail or {}
    for _, it in ipairs(outgoing.items) do
        c.mail[it.id] = (c.mail[it.id] or 0) + it.count
        if db.queue[outgoing.key] then db.queue[outgoing.key][it.id] = nil end
    end
    if db.queue[outgoing.key] and next(db.queue[outgoing.key]) == nil then db.queue[outgoing.key] = nil end
    c.mailMoney = (c.mailMoney or 0) + outgoing.money
    Print(("Posted to %s. It'll be waiting in their mailbox."):format(c.name))
    outgoing = nil
    if FM.UI and FM.UI.Refresh then FM.UI.Refresh() end
end

---------------------------------------------------------------------------
-- Tooltips
---------------------------------------------------------------------------
local function AddToTooltip(tooltip, id)
    if not db.settings.tooltip or not id or IsSecret(id) then return end
    local lines = FM.TooltipLines(id)
    if #lines == 0 then return end
    for i, l in ipairs(lines) do
        if i == 1 then
            tooltip:AddLine("|cffffd100" .. l[1] .. "|r")
        else
            local c = db.chars[l[3]]
            local col = (RAID_CLASS_COLORS and c.class and RAID_CLASS_COLORS[c.class]) or { r = 1, g = 1, b = 1 }
            tooltip:AddDoubleLine("  " .. l[1], l[2], col.r, col.g, col.b, 0.8, 0.8, 0.8)
        end
    end
    tooltip:Show()
end

local function HookTooltips()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
            if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
            local id = data and data.id
            if not id and tooltip.GetItem then
                local _, link = tooltip:GetItem()
                id = link and not IsSecret(link) and tonumber(link:match("item:(%d+)"))
            end
            pcall(AddToTooltip, tooltip, id)
        end)
    else
        for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
            if tt and tt.HookScript then
                tt:HookScript("OnTooltipSetItem", function(self)
                    local _, link = self:GetItem()
                    local id = link and tonumber(link:match("item:(%d+)"))
                    pcall(AddToTooltip, self, id)
                end)
            end
        end
    end
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local function Slash(msg)
    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    if cmd == "" or cmd == "show" then
        FM.UI.Toggle()
    elseif cmd == "tooltip" then
        db.settings.tooltip = not db.settings.tooltip
        Print("Tooltip lines " .. (db.settings.tooltip and "on." or "off."))
    elseif cmd == "mailpanel" then
        db.settings.mailPanel = not db.settings.mailPanel
        Print("Mailbox panel " .. (db.settings.mailPanel and "on." or "off."))
    elseif cmd == "forget" then
        local key = FM.FindCharacter(rest)
        if not key then Print("No character called '" .. rest .. "'.")
        elseif key == myKey then Print("That's you! Log in on another character to forget this one.")
        else
            db.chars[key] = nil
            db.queue[key] = nil
            Print("Forgot " .. key .. ".")
            if FM.UI.Refresh then FM.UI.Refresh() end
        end
    else
        Print("/fm - open the window")
        Print("/fm tooltip - family counts on item tooltips on/off")
        Print("/fm mailpanel - the 'Send to family' panel at mailboxes on/off")
        Print("/fm forget Name - forget a deleted or transferred character")
    end
end

function FamilyMailbox_Open() FM.UI.Toggle() end -- addon compartment

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
FM.frame = frame

local EVENTS = {
    "BAG_UPDATE", "BAG_UPDATE_DELAYED", "PLAYER_MONEY", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP",
    "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "PLAYERBANKSLOTS_CHANGED", "BANK_TABS_CHANGED",
    "MAIL_SHOW", "MAIL_CLOSED", "MAIL_INBOX_UPDATE", "MAIL_SEND_SUCCESS", "MAIL_FAILED", "UPDATE_PENDING_MAIL",
}

-- 1.0.0 filed Forever characters as "Name-Surname", as if the surname were a realm,
-- so every character looked like it was on its own realm. Re-file them by full name + ruleset.
function FM.MigrateRegional(group)
    local moves = {}
    for key, c in pairs(db.chars) do
        if not c.full then moves[#moves + 1] = key end
    end
    for _, old in ipairs(moves) do
        local c = db.chars[old]
        db.chars[old] = nil
        local surname = c.realm
        c.full = (surname and surname ~= "" and NormRealm(surname) ~= NormRealm(group)) and (c.name .. SurnameSep() .. surname) or c.name
        c.realm = group
        local new = c.full .. "-" .. NormRealm(group)
        if not db.chars[new] then db.chars[new] = c end
        if db.queue[old] then
            db.queue[new] = db.queue[new] or db.queue[old]
            db.queue[old] = nil
        end
    end
end

local function OnLogin()
    FamilyMailboxDB = FamilyMailboxDB or {}
    db = FamilyMailboxDB
    db.chars = db.chars or {}
    db.items = db.items or {}
    db.queue = db.queue or {}
    db.settings = db.settings or {}
    for k, v in pairs(DEFAULT_SETTINGS) do if db.settings[k] == nil then db.settings[k] = v end end

    local first, full, group, key = FM.Identity()
    myGroup = NormRealm(group)
    if Regional() then FM.MigrateRegional(group) end
    myKey = key
    db.chars[myKey] = db.chars[myKey] or { bags = {}, bank = {}, mail = {}, equipped = {} }
    me = db.chars[myKey]
    me.name, me.full, me.realm = first, full, group

    BuildBagLists()
    for _, ev in ipairs(EVENTS) do pcall(frame.RegisterEvent, frame, ev) end
    hooksecurefunc("SendMail", OnSendMail)
    HookTooltips()

    SLASH_FAMILYMAILBOX1 = "/fm"
    SLASH_FAMILYMAILBOX2 = "/familymailbox"
    SlashCmdList.FAMILYMAILBOX = Slash

    scan.info(); scan.bags(); scan.equipped()
    me.updated = time()
    if FM.UI and FM.UI.Init then FM.UI.Init() end
end

frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_LOGIN" then
        OnLogin()
    elseif event == "BAG_UPDATE" then
        if IsIn(BANK_IDS, arg1) and not IsIn(BAG_IDS, arg1) then
            if bankOpen then FM.Dirty("bank") end
        else
            FM.Dirty("bags")
        end
    elseif event == "BAG_UPDATE_DELAYED" then
        FM.Dirty("bags")
        if bankOpen then FM.Dirty("bank") end
    elseif event == "PLAYER_MONEY" or event == "PLAYER_LEVEL_UP" or event == "UPDATE_PENDING_MAIL" then
        FM.Dirty("info")
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        FM.Dirty("equipped")
    elseif event == "BANKFRAME_OPENED" then
        bankOpen, bankRetried = true, false
        FM.Dirty("bank")
    elseif event == "BANKFRAME_CLOSED" then
        bankOpen = false
    elseif event == "PLAYERBANKSLOTS_CHANGED" or event == "BANK_TABS_CHANGED" then
        if bankOpen then FM.Dirty("bank") end
    elseif event == "MAIL_SHOW" then
        if FM.UI.MailShow then FM.UI.MailShow() end
    elseif event == "MAIL_CLOSED" then
        if FM.UI.MailHide then FM.UI.MailHide() end
    elseif event == "MAIL_INBOX_UPDATE" then
        FM.Dirty("mail")
    elseif event == "MAIL_SEND_SUCCESS" then
        OnMailSent()
    elseif event == "MAIL_FAILED" then
        outgoing = nil
    end
end)
frame:RegisterEvent("PLAYER_LOGIN")
