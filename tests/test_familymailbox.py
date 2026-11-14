"""Runs Family Mailbox against a mock WoW API in real Lua 5.1.  pip install lupa  then:  python tests/test_familymailbox.py"""
import os, sys
try:
    from lupa import lua51 as L
except ImportError:
    import lupa as L

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
lua = L.LuaRuntime(unpack_returned_tuples=True)

MOCK = r'''
printed = {}
NOW = 1000000
function time() return NOW end
function tinsert(t, v) table.insert(t, v) end
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) printed[#printed+1] = m end }
timers = {}
C_Timer = { After = function(_, f) timers[#timers+1] = f end }
function run_timers() local t = timers; timers = {}; for _, f in ipairs(t) do f() end end

Widget = {}
Widget.__index = function(t, k)
  local v = rawget(Widget, k); if v ~= nil then return v end
  if type(k) == "string" and k:find("^%u") then return function() end end
end
function Widget:SetScript(k, fn) self.scripts[k] = fn end
function Widget:GetScript(k) return self.scripts[k] end
function Widget:HookScript(k, fn) self.scripts[k] = fn end
function Widget:RegisterEvent(e) self.events[e] = true end
function Widget:CreateFontString() return CreateFrame("FontString") end
function Widget:CreateTexture() return CreateFrame("Texture") end
function Widget:SetText(t) self.text = t end
function Widget:GetText() return self.text or "" end
function Widget:Show() self.shown = true; if self.scripts.OnShow then self.scripts.OnShow(self) end end
function Widget:Hide() self.shown = false end
function Widget:IsShown() return self.shown end
function Widget:SetHeight(h) self.height = h end
function Widget:AddLine(t) self.lines = self.lines or {}; self.lines[#self.lines+1] = t end
function Widget:AddDoubleLine(a, b) self.lines = self.lines or {}; self.lines[#self.lines+1] = a .. " | " .. b end
function CreateFrame(kind, name, parent, template)
  local f = setmetatable({ scripts = {}, events = {}, kind = kind }, Widget)
  if name then _G[name] = f end
  return f
end
UIParent = CreateFrame("Frame"); UISpecialFrames = {}
GameTooltip = CreateFrame("GameTooltip"); ItemRefTooltip = CreateFrame("GameTooltip")
RAID_CLASS_COLORS = { MAGE = { r = 0.25, g = 0.78, b = 0.92 }, WARRIOR = { r = 0.78, g = 0.61, b = 0.43 } }
function GetMoneyString(c) return tostring(c) .. "c" end
function issecretvalue(v) return v == "SECRET" end

-- the player
PLAYER = { name = "Dad", realm = "Mirage Raceway", class = "WARRIOR", level = 60, money = 50000 }
function UnitFullName() return PLAYER.name, PLAYER.realm end
function GetNormalizedRealmName() return (PLAYER.realm:gsub("%s", "")) end
function GetRealmName() return PLAYER.realm end
function UnitClass() return "Warrior", PLAYER.class end
function UnitFactionGroup() return "Alliance" end
function UnitLevel() return PLAYER.level end
function GetMoney() return PLAYER.money end

-- items: id -> link
LINKS = {}
local function link(id, name) LINKS[id] = "|cff1eff00|Hitem:" .. id .. "::::|h[" .. name .. "]|h|r"; return LINKS[id] end
link(2589, "Linen Cloth"); link(6948, "Hearthstone"); link(4306, "Silk Cloth"); link(12345, "Sword of Testing")
link(5000, "Ammo"); link(7000, "Bank Thing")
C_Item = {
  GetItemInfo = function(id) local l = LINKS[id]; if l then return l:match("%[(.-)%]"), l end end,
  GetItemIconByID = function(id) return 100 + id end,
}

-- containers: bag -> { slot -> info }
Enum = { BagIndex = { Backpack = 0, ReagentBag = 5, Keyring = -2,
  CharacterBankTab_1 = 6, CharacterBankTab_2 = 7, CharacterBankTab_3 = 8 },
  TooltipDataType = { Item = 0 } }
NUM_BAG_SLOTS = 4
CONTAINERS = {}
function put(bag, slot, id, count, bound)
  CONTAINERS[bag] = CONTAINERS[bag] or {}
  CONTAINERS[bag][slot] = id and { itemID = id, stackCount = count, hyperlink = LINKS[id], isBound = bound } or nil
end
calls = {}
C_Container = {
  GetContainerNumSlots = function(bag) if CONTAINERS[bag] then return 16 end return 0 end,
  GetContainerItemInfo = function(bag, slot) return CONTAINERS[bag] and CONTAINERS[bag][slot] end,
  PickupContainerItem = function(bag, slot) calls[#calls+1] = "pickup " .. bag .. ":" .. slot; cursor = { bag, slot } end,
}
EQUIP = { [16] = 12345, [0] = 5000 }
function GetInventoryItemID(_, slot) return EQUIP[slot] end
function GetInventoryItemLink(_, slot) return EQUIP[slot] and LINKS[EQUIP[slot]] end
function GetInventoryItemCount(_, slot) return slot == 0 and 200 or 1 end

-- mail
INBOX = {}
function GetInboxNumItems() return #INBOX end
function GetInboxHeaderInfo(i) local m = INBOX[i]; return nil, nil, m.sender, "subj", m.money, m.cod, 30 end
function GetInboxItem(i, a) local it = INBOX[i].items[a]; if it then return "x", it[1], 1, it[2] end end
function GetInboxItemLink(i, a) local it = INBOX[i].items[a]; return it and LINKS[it[1]] end
ATTACHMENTS_MAX_RECEIVE = 16; ATTACHMENTS_MAX_SEND = 12
SEND = {}
function GetSendMailItem(i) local it = SEND[i]; if it then return "x", it[1], 1, it[2] end end
function GetSendMailItemLink(i) return SEND[i] and LINKS[SEND[i][1]] end
function GetSendMailMoney() return SENDMONEY or 0 end
function ClickSendMailItemButton(i) if cursor then local inf = CONTAINERS[cursor[1]][cursor[2]]; SEND[i] = { inf.itemID, inf.stackCount }; cursor = nil end end
function ClearCursor() cursor = nil end
function MailFrameTab_OnClick(_, tab) calls[#calls+1] = "tab " .. tab end
SendMailNameEditBox = CreateFrame("EditBox"); SendMailSubjectEditBox = CreateFrame("EditBox")
MailFrame = CreateFrame("Frame")
SendMail = function() end
function hooksecurefunc(name, post) local o = _G[name]; _G[name] = function(...) o(...); post(...) end end

tooltipCallback = nil
TooltipDataProcessor = { AddTooltipPostCall = function(_, fn) tooltipCallback = fn end }
menus = {}
MenuUtil = { CreateContextMenu = function(owner, build)
  local root = { items = {} }
  function root:CreateTitle(t) self.items[#self.items+1] = { "title", t } end
  function root:CreateButton(t, fn) self.items[#self.items+1] = { "button", t, fn } end
  function root:CreateCheckbox(t, is, set) self.items[#self.items+1] = { "check", t, is, set } end
  build(owner, root); menus[#menus+1] = root
end }
SlashCmdList = {}
C_AddOns = {}
'''

passed = failed = 0
def check(name, cond):
    global passed, failed
    if cond:
        passed += 1
    else:
        failed += 1
        print("FAIL:", name)

lua.execute(MOCK)
for f in ("FamilyMailbox.lua", "FamilyMailbox_UI.lua"):
    src = open(os.path.join(ROOT, f), encoding="utf-8").read()
    lua.execute("local f = assert(loadstring(...)); f('FamilyMailbox')", src)

ev = lua.eval("function(e, ...) FamilyMailbox.frame:GetScript('OnEvent')(FamilyMailbox.frame, e, ...) end")
run = lua.execute

# ---- first login as Dad ---------------------------------------------------
run("put(0, 1, 2589, 20); put(0, 2, 6948, 1, true); put(1, 3, 4306, 10); put(-2, 1, 2589, 5)")
ev("PLAYER_LOGIN")
key = lua.eval("FamilyMailbox.MyKey()")
check("key uses normalized realm", key == "Dad-MirageRaceway")
check("bags scanned incl keyring", lua.eval("FamilyMailboxDB.chars['Dad-MirageRaceway'].bags[2589]") == 25)
check("equipped incl ammo stack", lua.eval("FamilyMailboxDB.chars['Dad-MirageRaceway'].equipped[5000]") == 200)
check("money", lua.eval("FamilyMailboxDB.chars['Dad-MirageRaceway'].money") == 50000)
check("slash registered", lua.eval("SlashCmdList.FAMILYMAILBOX ~= nil"))
check("tooltip hooked", lua.eval("tooltipCallback ~= nil"))

# bag change is debounced
run("put(0, 1, 2589, 15)")
ev("BAG_UPDATE", 0); ev("BAG_UPDATE", 1)
check("debounced: one timer", lua.eval("#timers") == 1)
run("run_timers()")
check("bags rescanned", lua.eval("FamilyMailboxDB.chars['Dad-MirageRaceway'].bags[2589]") == 20)

# bank: not scanned while closed, scanned when open
run("put(6, 1, 7000, 3)")
ev("BAG_UPDATE", 6); run("run_timers()")
check("bank ignored while closed", lua.eval("FamilyMailboxDB.chars['Dad-MirageRaceway'].bank[7000]") is None)
ev("BANKFRAME_OPENED"); run("run_timers()")
check("bank scanned on open", lua.eval("FamilyMailboxDB.chars['Dad-MirageRaceway'].bank[7000]") == 3)
check("bank seen time", lua.eval("FamilyMailboxDB.chars['Dad-MirageRaceway'].bankSeen") == 1000000)
ev("BANKFRAME_CLOSED")
run("put(6, 1, nil)")
ev("BAG_UPDATE", 6); run("run_timers()")
check("bank kept after closing", lua.eval("FamilyMailboxDB.chars['Dad-MirageRaceway'].bank[7000]") == 3)

# mailbox scan, COD money ignored
run("INBOX = { { sender='Bob', money=500, cod=0, items={ {4306, 4} } }, { sender='AH', money=0, cod=900, items={ {2589, 1}, {4306, 1} } } }")
ev("MAIL_SHOW"); ev("MAIL_INBOX_UPDATE"); run("run_timers()")
check("mail items", lua.eval("FamilyMailboxDB.chars['Dad-MirageRaceway'].mail[4306]") == 5)
check("mail money excludes COD", lua.eval("FamilyMailboxDB.chars['Dad-MirageRaceway'].mailMoney") == 500)
check("mail panel shown", lua.eval("FamilyMailboxMailPanel ~= nil and FamilyMailboxMailPanel:IsShown()"))
check("panel says no family yet", "Log in once" in (lua.eval("FamilyMailboxMailPanel.empty:GetText()") or ""))
ev("MAIL_CLOSED")
run("INBOX = {}")

# ---- log in as Tahu (the kid) on the same realm ---------------------------
run("""
local saved = FamilyMailboxDB
dofile_reset = true
PLAYER = { name = "Tahu", realm = "Mirage Raceway", class = "MAGE", level = 12, money = 300 }
CONTAINERS = {}; EQUIP = {}
put(0, 1, 2589, 2)
""")
lua.execute("FamilyMailboxDB = ...", lua.eval("FamilyMailboxDB"))
for f in ("FamilyMailbox.lua", "FamilyMailbox_UI.lua"):
    src = open(os.path.join(ROOT, f), encoding="utf-8").read()
    lua.execute("local f = assert(loadstring(...)); f('FamilyMailbox')", src)
ev = lua.eval("function(e, ...) FamilyMailbox.frame:GetScript('OnEvent')(FamilyMailbox.frame, e, ...) end")
ev("PLAYER_LOGIN")
check("two characters", lua.eval("#FamilyMailbox.Characters()") == 2)
check("Dad kept", lua.eval("FamilyMailboxDB.chars['Dad-MirageRaceway'].bank[7000]") == 3)
check("find character any case", lua.eval("FamilyMailbox.FindCharacter('dad')") == "Dad-MirageRaceway")
check("find with realm", lua.eval("FamilyMailbox.FindCharacter('Dad-Mirage Raceway')") == "Dad-MirageRaceway")
check("postable = Dad only", lua.eval("#FamilyMailbox.Postable()") == 1 and lua.eval("FamilyMailbox.Postable()[1]") == "Dad-MirageRaceway")

# search
res = lua.eval("FamilyMailbox.Search('cloth')")
names = [res[i].name for i in range(1, len(res) + 1)]
check("search finds cloth across family", names == ["Linen Cloth", "Silk Cloth"])
check("linen total = Dad 20 bags + 1 mail + Tahu 2", res[1].total == 23)
check("search one character", len(lua.eval("FamilyMailbox.Search('', 'Tahu-MirageRaceway')")) == 1)
check("total gold incl mail", lua.eval("FamilyMailbox.TotalMoney()") == 50000 + 500 + 300)

# tooltip
lines = lua.eval("FamilyMailbox.TooltipLines(2589)")
check("tooltip header", lines[1][1] == "Family has 23")
check("tooltip shows Dad", any(lines[i][1] == "Dad" and "bags 20" in lines[i][2] for i in range(2, len(lines) + 1)))
check("tooltip silent when only in my bags", len(lua.eval("FamilyMailbox.TooltipLines(99999)")) == 0)
run("tooltipCallback(GameTooltip, { id = 7000 })")
check("tooltip lines added", any("bank 3" in l for l in lua.eval("GameTooltip.lines").values()))
run("GameTooltip.lines = nil; tooltipCallback(GameTooltip, { id = 'SECRET' })")
check("secret id ignored", lua.eval("GameTooltip.lines") is None)
run("FamilyMailboxDB.settings.tooltip = false; tooltipCallback(GameTooltip, { id = 7000 })")
check("tooltip setting off", lua.eval("GameTooltip.lines") is None)
run("FamilyMailboxDB.settings.tooltip = true")

# window
run("FamilyMailbox.UI.Toggle()")
check("window open", lua.eval("FamilyMailbox.UI.IsShown()"))
check("window lists items", len(lua.eval("FamilyMailbox.UI.Results()")) >= 5)
check("Everyone + 2 chars", lua.eval("FamilyMailboxFrame.charButtons[3]:IsShown()") and not lua.eval("FamilyMailboxFrame.charButtons[4]:IsShown()"))
run("FamilyMailboxSearch:SetText('silk'); FamilyMailboxSearch:GetScript('OnTextChanged')(FamilyMailboxSearch)")
check("search box filters", len(lua.eval("FamilyMailbox.UI.Results()")) == 1)
run("FamilyMailboxFrame.charButtons[2]:GetScript('OnClick')(FamilyMailboxFrame.charButtons[2], 'LeftButton')")
check("select character", lua.eval("FamilyMailbox.UI.State().selected") is not None)

# ---- queue: Dad queues silk for Tahu, from Tahu's login it shows ------------
run("FamilyMailbox.ToggleQueue('Dad-MirageRaceway', 2589)")
check("queued", lua.eval("FamilyMailbox.IsQueued('Dad-MirageRaceway', 2589)"))
run("FamilyMailbox.UI.State().mode = 'queue'; FamilyMailbox.UI.Refresh()")
check("queue view lists it", len(lua.eval("FamilyMailbox.UI.Results()")) == 1)
run("FamilyMailboxFrame.rows[1]:GetScript('OnClick')(FamilyMailboxFrame.rows[1], 'LeftButton')")
check("click removes from queue", not lua.eval("FamilyMailbox.IsQueued('Dad-MirageRaceway', 2589)"))
check("empty queue table cleaned", lua.eval("FamilyMailboxDB.queue['Dad-MirageRaceway']") is None)

# right-click menu -> checkbox queues
run("FamilyMailbox.UI.State().mode = 'items'; FamilyMailboxSearch:SetText(''); FamilyMailbox.UI.State().search = ''; FamilyMailbox.UI.State().selected = nil; FamilyMailbox.UI.Refresh()")
run("""
local row
for _, r in ipairs(FamilyMailboxFrame.rows) do if r.id == 2589 then row = r end end
row:GetScript('OnClick')(row, 'RightButton')
local m = menus[#menus]
assert(m.items[1][1] == 'title')
m.items[2][4]()
""")
check("menu checkbox queues for Dad", lua.eval("FamilyMailbox.IsQueued('Dad-MirageRaceway', 2589)"))

# ---- at the mailbox: prepare a letter to Dad ---------------------------------
run("put(0, 2, 2589, 3); put(0, 3, 2589, 1, true)")
ev("MAIL_SHOW")
check("panel has Dad button", lua.eval("FamilyMailboxMailPanel.buttons[1]:IsShown()"))
check("panel shows count", "(2 to post)" in lua.eval("FamilyMailboxMailPanel.buttons[1]:GetText()"))
run("calls = {}; FamilyMailboxMailPanel.buttons[1]:GetScript('OnClick')(FamilyMailboxMailPanel.buttons[1])")
check("switched to send tab", lua.eval("calls[1]") == "tab 2")
check("recipient filled", lua.eval("SendMailNameEditBox:GetText()") == "Dad")
check("two stacks attached, bound skipped", lua.eval("SEND[1][2]") == 2 and lua.eval("SEND[2][2]") == 3 and lua.eval("SEND[3]") is None)
check("subject filled", lua.eval("SendMailSubjectEditBox:GetText()") == "From Tahu")
check("told about soulbound", any("soulbound" in str(v) for v in lua.eval("printed").values()))

# sending it
run("SENDMONEY = 100; SendMail('Dad', 'From Tahu', '')")
ev("MAIL_SEND_SUCCESS")
check("Dad's mail gets the items", lua.eval("FamilyMailboxDB.chars['Dad-MirageRaceway'].mail[2589]") == 6)
check("Dad's mail money", lua.eval("FamilyMailboxDB.chars['Dad-MirageRaceway'].mailMoney") == 600)
check("queue cleared after posting", not lua.eval("FamilyMailbox.IsQueued('Dad-MirageRaceway', 2589)"))
run("SEND = {}; SENDMONEY = 0; SendMail('Stranger', 's', '')")
ev("MAIL_SEND_SUCCESS")
check("mail to strangers not tracked", lua.eval("FamilyMailbox.FindCharacter('Stranger')") is None)
run("SEND = { {2589, 1} }; SendMail('Dad', 's', '')"); ev("MAIL_FAILED"); ev("MAIL_SEND_SUCCESS")
check("failed mail not counted", lua.eval("FamilyMailboxDB.chars['Dad-MirageRaceway'].mail[2589]") == 6)

# full letter: 13 stacks queued -> 12 attached, 1 left
run("SEND = {}; for s = 1, 13 do put(2, s, 4306, 1) end; FamilyMailbox.ToggleQueue('Dad-MirageRaceway', 4306)")
a, left, bound = lua.eval("FamilyMailbox.PrepareMail('Dad-MirageRaceway')")
check("12 attached 1 left", a == 12 and left == 1)

# slash
run("SlashCmdList.FAMILYMAILBOX('forget Tahu')")
check("can't forget yourself", lua.eval("FamilyMailboxDB.chars['Tahu-MirageRaceway']") is not None)
run("SlashCmdList.FAMILYMAILBOX('forget dad')")
check("forget Dad", lua.eval("FamilyMailboxDB.chars['Dad-MirageRaceway']") is None and lua.eval("FamilyMailboxDB.queue['Dad-MirageRaceway']") is None)
run("SlashCmdList.FAMILYMAILBOX('tooltip')")
check("tooltip toggle", lua.eval("FamilyMailboxDB.settings.tooltip") is False)
run("SlashCmdList.FAMILYMAILBOX('help')")
run("FamilyMailbox.UI.Refresh()")
check("window survives forgotten char", lua.eval("FamilyMailbox.UI.IsShown()"))


# ---- WoW Forever: surnames instead of realms (regression for 1.0.0) --------
lua2 = L.LuaRuntime(unpack_returned_tuples=True)
lua2.execute(MOCK)
lua2.execute("""
RegionalUniqueNamesEnabled = function() return true end
Enum.GameRule = { PvPRuleset = 1, RPRuleset = 2, HardcoreRuleset = 3 }
C_GameRules = { IsGameRuleActive = function(r) return r == 1 end }
PLAYER = { name = "Gromir", realm = "Crypmaghar", class = "MAGE", level = 60, money = 900000 }
function UnitNameUnmodified() return "Gromir", "Crypmaghar" end
function HasNewMail() return NEWMAIL end
NEWMAIL = true
CONTAINERS = {}; EQUIP = {}
put(0, 1, 4306, 7)
-- what 1.0.0 saved: surname filed as if it were the realm
FamilyMailboxDB = { items = {}, queue = { ['Tahu-Hoardhoof'] = { [2589] = true } }, settings = {}, chars = {
  ['Gromir-Crypmaghar'] = { name = 'Gromir', realm = 'Crypmaghar', class = 'MAGE', bags = {}, bank = { [7000] = 2 }, mail = {}, equipped = {} },
  ['Tahu-Hoardhoof'] = { name = 'Tahu', realm = 'Hoardhoof', class = 'MAGE', level = 12, bags = { [2589] = 1 }, bank = {}, mail = {}, equipped = {} },
} }
""")
for f in ("FamilyMailbox.lua", "FamilyMailbox_UI.lua"):
    src = open(os.path.join(ROOT, f), encoding="utf-8").read()
    lua2.execute("local f = assert(loadstring(...)); f('FamilyMailbox')", src)
ev2 = lua2.eval("function(e, ...) FamilyMailbox.frame:GetScript('OnEvent')(FamilyMailbox.frame, e, ...) end")
ev2("PLAYER_LOGIN")
check("regional key = full name + ruleset", lua2.eval("FamilyMailbox.MyKey()") == "Gromir Crypmaghar-PvP")
check("old records re-filed", lua2.eval("FamilyMailboxDB.chars['Gromir-Crypmaghar']") is None and lua2.eval("FamilyMailboxDB.chars['Tahu Hoardhoof-PvP'] ~= nil"))
check("old bank data kept", lua2.eval("FamilyMailboxDB.chars['Gromir Crypmaghar-PvP'].bank[7000]") == 2)
check("queue re-filed", lua2.eval("FamilyMailbox.IsQueued('Tahu Hoardhoof-PvP', 2589)"))
check("Tahu is postable from Gromir", lua2.eval("#FamilyMailbox.Postable()") == 1)
check("find by full name", lua2.eval("FamilyMailbox.FindCharacter('tahu hoardhoof')") == "Tahu Hoardhoof-PvP")
check("find by unique first name", lua2.eval("FamilyMailbox.FindCharacter('Tahu')") == "Tahu Hoardhoof-PvP")
check("unread mail flag", lua2.eval("FamilyMailboxDB.chars['Gromir Crypmaghar-PvP'].unreadMail") is True)
lua2.execute("put(0, 2, 2589, 4)")
lua2.execute("FamilyMailbox.PrepareMail('Tahu Hoardhoof-PvP')")
check("mail addressed to full name", lua2.eval("SendMailNameEditBox:GetText()") == "Tahu Hoardhoof")
lua2.execute("SendMail('Tahu Hoardhoof', 's', '')"); ev2("MAIL_SEND_SUCCESS")
check("posted mail tracked for Tahu", lua2.eval("FamilyMailboxDB.chars['Tahu Hoardhoof-PvP'].mail[2589]") == 4)
# mailbox view
lua2.execute("INBOX = { { sender='AH', money=0, cod=0, items={ {12345, 1} } } }; NEWMAIL = false")
ev2("MAIL_SHOW"); ev2("MAIL_INBOX_UPDATE"); ev2("UPDATE_PENDING_MAIL"); lua2.execute("run_timers()")
check("Gromir mailbox recorded", lua2.eval("FamilyMailboxDB.chars['Gromir Crypmaghar-PvP'].mail[12345]") == 1)
check("unread flag clears", lua2.eval("FamilyMailboxDB.chars['Gromir Crypmaghar-PvP'].unreadMail") is False)
check("search by location", len(lua2.eval("FamilyMailbox.Search('', nil, 'mail')")) == 2 and len(lua2.eval("FamilyMailbox.Search('', 'Gromir Crypmaghar-PvP', 'mail')")) == 1)
lua2.execute("FamilyMailbox.UI.Toggle(); local b = FamilyMailboxFrame.locButtons[4]; b:GetScript('OnClick')(b)")
check("Mail button filters window", lua2.eval("FamilyMailbox.UI.State().loc") == "mail" and len(lua2.eval("FamilyMailbox.UI.Results()")) == 2)
check("panel button shows full name", "Tahu Hoardhoof" in lua2.eval("FamilyMailboxMailPanel.buttons[1]:GetText()"))


# ---- Syndicator import: characters/banks we haven't seen ourselves -------------
lua3 = L.LuaRuntime(unpack_returned_tuples=True)
lua3.execute(MOCK)
lua3.execute("""
RegionalUniqueNamesEnabled = function() return true end
Enum.GameRule = { PvPRuleset = 1 }
C_GameRules = { IsGameRuleActive = function(r) return r == 1 end }
PLAYER = { name = "Gromir", realm = "Crypmaghar", class = "MAGE", level = 25, money = 840 }
function UnitNameUnmodified() return "Gromir", "Crypmaghar" end
CONTAINERS = {}; EQUIP = {}
local function it(id, n) return { itemID = id, itemCount = n, itemLink = LINKS[id] } end
SYNDICATOR_DATA = { Characters = {
  ['Gromir Crypmaghar-PvP'] = { details = { character = 'Gromir Crypmaghar', realmNormalized = 'PvP', className = 'MAGE', faction = 'Horde' },
     money = 840, bags = { { it(2589, 3) } }, bankTabs = { { slots = { it(7000, 4), {}, it(7000, 1) } } }, mail = {}, equipped = {} },
  ['Aldric Lastlight-PvP'] = { details = { character = 'Aldric Lastlight', realmNormalized = 'PvP', className = 'WARRIOR', faction = 'Horde' },
     money = 7833, bags = { { it(4306, 9) } }, bankTabs = {}, mail = { it(12345, 1) }, equipped = { it(6948, 1) } },
  ['Broken'] = { },
} }
FamilyMailboxDB = { chars = { ['Gromir Crypmaghar-PvP'] = { name = 'Gromir', full = 'Gromir Crypmaghar', realm = 'PvP', bags = {}, bank = {}, mail = {}, equipped = {} } } }
""")
for f in ("FamilyMailbox.lua", "FamilyMailbox_UI.lua"):
    lua3.execute("local f = assert(loadstring(...)); f('FamilyMailbox')", open(os.path.join(ROOT, f), encoding="utf-8").read())
lua3.eval("function() FamilyMailbox.frame:GetScript('OnEvent')(FamilyMailbox.frame, 'PLAYER_LOGIN') end")()
check("syndicator: new character imported", lua3.eval("FamilyMailboxDB.chars['Aldric Lastlight-PvP'] ~= nil"))
check("syndicator: their bags/mail/worn/gold", lua3.eval("FamilyMailboxDB.chars['Aldric Lastlight-PvP'].bags[4306]") == 9
      and lua3.eval("FamilyMailboxDB.chars['Aldric Lastlight-PvP'].mail[12345]") == 1
      and lua3.eval("FamilyMailboxDB.chars['Aldric Lastlight-PvP'].equipped[6948]") == 1
      and lua3.eval("FamilyMailboxDB.chars['Aldric Lastlight-PvP'].money") == 7833)
check("syndicator: my unopened bank filled", lua3.eval("FamilyMailboxDB.chars['Gromir Crypmaghar-PvP'].bank[7000]") == 5)
check("syndicator: my live bags not overwritten", lua3.eval("FamilyMailboxDB.chars['Gromir Crypmaghar-PvP'].bags[2589]") is None)
check("syndicator: postable", lua3.eval("#FamilyMailbox.Postable()") == 1)
lua3.execute("put(6, 1, 7000, 2)")
lua3.eval("function() FamilyMailbox.frame:GetScript('OnEvent')(FamilyMailbox.frame, 'BANKFRAME_OPENED') end")()
lua3.execute("run_timers()")
check("own bank scan replaces imported", lua3.eval("FamilyMailboxDB.chars['Gromir Crypmaghar-PvP'].bank[7000]") == 2
      and lua3.eval("FamilyMailboxDB.chars['Gromir Crypmaghar-PvP'].bankFromSyndicator") is None)

print(f"{passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
