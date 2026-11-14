--[[
    Family Mailbox windows:
      * Main window  - /fm or the addon compartment: characters on the left, items on the right
      * Mail panel   - sits beside the mailbox: one click addresses a letter to a family member
                       and attaches everything queued for them
]]

local FM = FamilyMailbox
local UI = {}
FM.UI = UI

local GOLD = "|cffffd100"
local GREY = "|cffaaaaaa"
local GREEN = "|cff33ff66"

local ROWS = 11
local ROW_H = 30
local CHAR_ROWS = 12

local state = { selected = nil, search = "", offset = 0, mode = "items", loc = nil }
local win, results

---------------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------------
local function ClassHex(class)
    local c = RAID_CLASS_COLORS and class and RAID_CLASS_COLORS[class]
    if not c then return "|cffffffff" end
    return ("|cff%02x%02x%02x"):format(c.r * 255, c.g * 255, c.b * 255)
end

local function Money(copper)
    copper = copper or 0
    if GetMoneyString then return GetMoneyString(copper, true) end
    return ("%dg %ds %dc"):format(copper / 10000, (copper / 100) % 100, copper % 100)
end

local function Ago(t)
    if not t then return nil end
    local s = time() - t
    if s < 3600 then return "just now" end
    if s < 86400 then return math.floor(s / 3600) .. "h ago" end
    return math.floor(s / 86400) .. " days ago"
end

local function CharLabel(key)
    local c = FM.DB().chars[key]
    return ClassHex(c.class) .. FM.FullName(c) .. "|r"
end

local function Text(parent, template)
    local fs = parent:CreateFontString(nil, "ARTWORK", template or "GameFontHighlight")
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    return fs
end

local function Button(parent, label, w, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    return b
end

local function Window(name, w, h, title)
    local ok, f = pcall(CreateFrame, "Frame", name, UIParent, "BasicFrameTemplateWithInset")
    if not ok or not f then
        f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
        if f.SetBackdrop then
            f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
                edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 32,
                insets = { left = 8, right = 8, top = 8, bottom = 8 } })
        end
    end
    f:SetSize(w, h)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    local t = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    t:SetPoint("TOP", 0, -5)
    t:SetText(GOLD .. "Family Mailbox|r" .. (title and ("  " .. title) or ""))
    f:Hide()
    tinsert(UISpecialFrames, name)
    return f
end

local function ContextMenu(owner, build)
    if MenuUtil and MenuUtil.CreateContextMenu then
        MenuUtil.CreateContextMenu(owner, build)
        return true
    end
end

---------------------------------------------------------------------------
-- Main window
---------------------------------------------------------------------------
local function BuildWindow()
    win = Window("FamilyMailboxFrame", 700, 470)

    -- left: characters ------------------------------------------------------
    local head = Text(win, "GameFontNormal")
    head:SetPoint("TOPLEFT", 16, -34)
    head:SetText("Characters")

    win.charButtons = {}
    for i = 1, CHAR_ROWS + 1 do
        local b = CreateFrame("Button", nil, win)
        b:SetSize(180, 26)
        b:SetPoint("TOPLEFT", 12, -52 - (i - 1) * 27)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.08)
        b.sel = b:CreateTexture(nil, "BACKGROUND")
        b.sel:SetAllPoints()
        b.sel:SetColorTexture(1, 0.82, 0, 0.18)
        b.name = Text(b, "GameFontHighlight")
        b.name:SetPoint("TOPLEFT", 6, -2)
        b.name:SetWidth(170)
        b.sub = Text(b, "GameFontHighlightSmall")
        b.sub:SetPoint("BOTTOMLEFT", 6, 2)
        b.sub:SetWidth(170)
        b:SetScript("OnClick", function(self, button)
            if button == "RightButton" and self.key and self.key ~= FM.MyKey() then
                local key = self.key
                local shown = ContextMenu(self, function(_, root)
                    root:CreateTitle(FM.DB().chars[key].name)
                    root:CreateButton("Forget this character", function()
                        FM.DB().chars[key] = nil
                        FM.DB().queue[key] = nil
                        if state.selected == key then state.selected = nil end
                        UI.Refresh()
                    end)
                end)
                if not shown then FM.Print("Type /fm forget " .. FM.DB().chars[key].name .. " to forget them.") end
                return
            end
            state.selected = self.key
            state.offset = 0
            UI.Refresh()
        end)
        win.charButtons[i] = b
    end

    win.gold = Text(win, "GameFontHighlightSmall")
    win.gold:SetPoint("BOTTOMLEFT", 16, 14)
    win.gold:SetWidth(180)

    -- right: search, tabs and the list -------------------------------------
    local search = CreateFrame("EditBox", "FamilyMailboxSearch", win, "InputBoxTemplate")
    search:SetSize(200, 22)
    search:SetPoint("TOPLEFT", 214, -32)
    search:SetAutoFocus(false)
    search:SetScript("OnTextChanged", function(self)
        state.search = self:GetText() or ""
        state.offset = 0
        UI.Refresh()
    end)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    search.hint = Text(search, "GameFontDisable")
    search.hint:SetPoint("LEFT", 4, 0)
    search.hint:SetText("Search items...")
    win.search = search

    win.itemsTab = Button(win, "Items", 80, function() state.mode = "items"; state.offset = 0; UI.Refresh() end)
    win.itemsTab:SetPoint("LEFT", search, "RIGHT", 12, 0)
    win.queueTab = Button(win, "To post", 110, function() state.mode = "queue"; state.offset = 0; UI.Refresh() end)
    win.queueTab:SetPoint("LEFT", win.itemsTab, "RIGHT", 4, 0)

    win.info = Text(win, "GameFontHighlightSmall")
    win.info:SetPoint("TOPLEFT", 214, -60)
    win.info:SetWidth(230)

    -- where to look: everywhere, or just one place
    win.locButtons = {}
    local prev
    for _, l in ipairs({ { nil, "All" }, { "bags", "Bags" }, { "bank", "Bank" }, { "mail", "Mail" }, { "equipped", "Worn" } }) do
        local loc = l[1]
        local b = Button(win, l[2], 46, function()
            state.loc = loc
            state.mode = "items"
            state.offset = 0
            UI.Refresh()
        end)
        b:SetHeight(18)
        b.loc = loc
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 2, 0) else b:SetPoint("TOPRIGHT", win, "TOPRIGHT", -16 - 4 * 48, -56) end
        prev = b
        win.locButtons[#win.locButtons + 1] = b
    end

    win.rows = {}
    for i = 1, ROWS do
        local r = CreateFrame("Button", nil, win)
        r:SetSize(470, ROW_H)
        r:SetPoint("TOPLEFT", 210, -76 - (i - 1) * ROW_H)
        r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        local hl = r:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.08)
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(24, 24)
        r.icon:SetPoint("LEFT", 4, 0)
        r.name = Text(r, "GameFontHighlight")
        r.name:SetPoint("TOPLEFT", 34, -2)
        r.name:SetWidth(360)
        r.count = r:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        r.count:SetPoint("TOPRIGHT", -6, -2)
        r.count:SetJustifyH("RIGHT")
        r.where = Text(r, "GameFontHighlightSmall")
        r.where:SetPoint("BOTTOMLEFT", 34, 2)
        r.where:SetWidth(430)
        r:SetScript("OnEnter", function(self)
            if not self.id then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local link = FM.ItemLink(self.id)
            if link then GameTooltip:SetHyperlink(link) else GameTooltip:SetItemByID(self.id) end
            GameTooltip:AddLine(GREY .. "Right-click to choose who to post it to.|r")
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        r:SetScript("OnClick", function(self, button)
            if not self.id then return end
            if IsModifiedClick and IsModifiedClick("CHATLINK") and ChatEdit_InsertLink then
                ChatEdit_InsertLink(FM.ItemLink(self.id))
                return
            end
            if state.mode == "queue" and self.recipient then
                FM.ToggleQueue(self.recipient, self.id)
                return
            end
            if button == "RightButton" then UI.PostMenu(self, self.id) end
        end)
        win.rows[i] = r
    end

    win:EnableMouseWheel(true)
    win:SetScript("OnMouseWheel", function(_, delta)
        state.offset = math.max(0, math.min(state.offset - delta * 3, math.max(0, #results - ROWS)))
        UI.Refresh()
    end)

    win.page = Text(win, "GameFontHighlightSmall")
    win.page:SetPoint("BOTTOMRIGHT", -16, 34)
    win.page:SetJustifyH("RIGHT")

    win.seen = Text(win, "GameFontHighlightSmall")
    win.seen:SetPoint("BOTTOMLEFT", 214, 14)
    win.seen:SetWidth(420)

    win:SetScript("OnShow", function() UI.Refresh() end)
end

-- "Post to..." menu for an item
function UI.PostMenu(owner, id)
    local targets = FM.Postable()
    if #targets == 0 then
        FM.Print("No other characters on this realm yet. Log in on them once so Family Mailbox knows them.")
        return
    end
    local shown = ContextMenu(owner, function(_, root)
        root:CreateTitle("Post " .. FM.ItemName(id) .. " to...")
        for _, key in ipairs(targets) do
            root:CreateCheckbox(CharLabel(key),
                function() return FM.IsQueued(key, id) end,
                function() FM.ToggleQueue(key, id) end)
        end
    end)
    if not shown then FM.ToggleQueue(targets[1], id) end
end

local function FillCharacters()
    local list = FM.Characters()
    local db = FM.DB()
    local i = 1
    local function Set(b, key, name, sub)
        b.key = key
        b.name:SetText(name)
        b.sub:SetText(sub)
        if state.selected == key then b.sel:Show() else b.sel:Hide() end
        b:Show()
    end
    Set(win.charButtons[1], nil, GOLD .. "Everyone|r", GREY .. #list .. " characters|r")
    for _, key in ipairs(list) do
        i = i + 1
        local b = win.charButtons[i]
        if not b then break end
        local c = db.chars[key]
        local tag = key == FM.MyKey() and (GREEN .. " (you)|r") or ""
        local mail = c.unreadMail and (GOLD .. "  mail waiting|r") or ""
        Set(b, key, CharLabel(key) .. tag, GREY .. (c.level and ("Lv " .. c.level .. "  ") or "") .. "|r" .. Money(c.money) .. mail)
    end
    for j = i + 1, #win.charButtons do win.charButtons[j]:Hide(); win.charButtons[j].key = nil end
    win.gold:SetText("Family gold: " .. Money(FM.TotalMoney()))
end

local function QueueResults()
    local list, db = {}, FM.DB()
    for _, key in ipairs(FM.Characters()) do
        for id in pairs(db.queue[key] or {}) do
            local mine = select(2, FM.Count(FM.MyKey(), id)).bags
            list[#list + 1] = { id = id, name = FM.ItemName(id), recipient = key, mine = mine }
        end
    end
    table.sort(list, function(a, b)
        if a.recipient ~= b.recipient then return a.recipient < b.recipient end
        return a.name < b.name
    end)
    return list
end

function UI.Refresh()
    if not win or not win:IsShown() then return end
    local db = FM.DB()
    if state.selected and not db.chars[state.selected] then state.selected = nil end
    FillCharacters()

    if state.search == "" then win.search.hint:Show() else win.search.hint:Hide() end
    local queued = 0
    for key in pairs(db.queue) do queued = queued + FM.QueueCount(key) end
    win.queueTab:SetText("To post (" .. queued .. ")")
    for _, b in ipairs(win.locButtons) do
        if state.mode == "items" and b.loc == state.loc then b:Disable() else b:Enable() end
    end

    if state.mode == "queue" then
        results = QueueResults()
        win.info:SetText(#results == 0
            and (GREY .. "Nothing waiting. Right-click any item in the Items list to post it to another character.|r")
            or (GREY .. "Visit a mailbox and press a name in the 'Send to family' panel. Click a row to take it off the list.|r"))
    else
        results = FM.Search(state.search, state.selected, state.loc)
        local who = state.selected and CharLabel(state.selected) or "everyone"
        local where = state.loc and (" in " .. FM.LOCATION_LABEL[state.loc]) or ""
        win.info:SetText(GREY .. #results .. " items" .. where .. " for |r" .. who)
    end

    state.offset = math.max(0, math.min(state.offset, math.max(0, #results - ROWS)))
    for i, r in ipairs(win.rows) do
        local res = results[state.offset + i]
        if res then
            r.id = res.id
            r.recipient = res.recipient
            r.icon:SetTexture(FM.ItemIcon(res.id))
            r.name:SetText(FM.ItemLink(res.id) or res.name)
            if state.mode == "queue" then
                r.count:SetText("")
                local have = (res.mine or 0) > 0 and ("you have " .. res.mine .. " in your bags") or "not in your bags"
                r.where:SetText("for " .. CharLabel(res.recipient) .. GREY .. "  -  " .. have .. "|r")
            else
                r.count:SetText(res.total)
                for _, key in ipairs(FM.Postable()) do
                    if FM.IsQueued(key, res.id) then
                        r.name:SetText((FM.ItemLink(res.id) or res.name) .. GREEN .. "  (to post to " .. FM.DB().chars[key].name .. ")|r")
                        break
                    end
                end
                local parts = {}
                for _, h in ipairs(res.holders) do
                    parts[#parts + 1] = CharLabel(h.key) .. GREY .. " " .. FM.WhereText(h.where) .. "|r"
                end
                r.where:SetText(table.concat(parts, "   "))
            end
            r:Show()
        else
            r.id, r.recipient = nil, nil
            r:Hide()
        end
    end

    if #results > ROWS then
        win.page:SetText(GREY .. (state.offset + 1) .. "-" .. math.min(#results, state.offset + ROWS) .. " of " .. #results .. "  (scroll)|r")
    else
        win.page:SetText("")
    end

    local c = state.selected and db.chars[state.selected]
    if c then
        local bank = c.bankSeen and ("bank " .. Ago(c.bankSeen))
            or (c.bankFromSyndicator and "bank from Syndicator") or "bank never opened"
        local mail = c.mailSeen and ("mailbox " .. Ago(c.mailSeen))
            or (c.mailFromSyndicator and "mailbox from Syndicator") or "mailbox never opened"
        local waiting = c.unreadMail and (GOLD .. "  Unread mail waiting: open a mailbox to see it.|r") or ""
        win.seen:SetText(GREY .. "Last seen: " .. bank .. ", " .. mail .. "|r" .. waiting)
    else
        win.seen:SetText(GREY .. "Open the bank and mailbox once on each character to fill them in.|r")
    end
end

function UI.Toggle()
    if not win then BuildWindow() end
    if win:IsShown() then win:Hide() else win:Show() end
end

function UI.IsShown() return win ~= nil and win:IsShown() end
function UI.Results() return results end -- tests
function UI.State() return state end     -- tests

---------------------------------------------------------------------------
-- Mailbox panel
---------------------------------------------------------------------------
local panel

local function BuildPanel()
    panel = CreateFrame("Frame", "FamilyMailboxMailPanel", MailFrame or UIParent, "BackdropTemplate")
    panel:SetSize(190, 60)
    if MailFrame then
        panel:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", 4, 0)
    else
        panel:SetPoint("LEFT", 40, 0)
    end
    if panel.SetBackdrop then
        panel:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 } })
        panel:SetBackdropColor(0, 0, 0, 0.85)
    end
    panel.title = Text(panel, "GameFontNormal")
    panel.title:SetPoint("TOPLEFT", 10, -10)
    panel.title:SetText("Send to family")
    panel.empty = Text(panel, "GameFontHighlightSmall")
    panel.empty:SetPoint("TOPLEFT", 10, -30)
    panel.empty:SetWidth(170)
    panel.empty:SetWordWrap(true)
    panel.buttons = {}
    panel.open = Button(panel, "Open Family Mailbox", 170, function() UI.Toggle() end)
    panel:Hide()
end

function UI.MailRefresh()
    if not panel or not panel:IsShown() then return end
    local targets = FM.Postable()
    for _, b in ipairs(panel.buttons) do b:Hide() end
    local y = -30
    if #targets == 0 then
        panel.empty:SetText(GREY .. "Log in once on your other characters on this realm and they'll appear here.|r")
        panel.empty:Show()
        y = y - 44
    else
        panel.empty:Hide()
        for i, key in ipairs(targets) do
            local b = panel.buttons[i]
            if not b then
                b = Button(panel, "", 170, function(self)
                    local attached, left, bound = FM.PrepareMail(self.key)
                    local name = FM.DB().chars[self.key].name
                    if attached > 0 then
                        FM.Print(("Attached %d for %s. Check it, then press Send."):format(attached, name))
                    else
                        FM.Print("Addressed to " .. name .. ".")
                    end
                    if left > 0 then FM.Print(left .. " more will fit in the next letter. Press " .. name .. " again after sending.") end
                    if bound > 0 then FM.Print(bound .. " queued item(s) are soulbound and can't be posted.") end
                end)
                panel.buttons[i] = b
            end
            b.key = key
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", 10, y)
            local n = #(FM.QueuedInBags(key))
            b:SetText(FM.FullName(FM.DB().chars[key]) .. (n > 0 and ("  (" .. n .. " to post)") or ""))
            b:Show()
            y = y - 24
        end
    end
    panel.open:ClearAllPoints()
    panel.open:SetPoint("TOPLEFT", 10, y - 6)
    panel:SetHeight(-y + 40)
end

function UI.MailShow()
    if not FM.DB().settings.mailPanel then return end
    if not panel then BuildPanel() end
    panel:Show()
    UI.MailRefresh()
end

function UI.MailHide()
    if panel then panel:Hide() end
end

local baseRefresh = UI.Refresh
UI.Refresh = function()
    baseRefresh()
    UI.MailRefresh()
end

function UI.Init() end
