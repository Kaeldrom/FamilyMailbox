"""Hand-me-downs: gear and profession materials one character could pass to another.
Uses the same mock WoW API as test_familymailbox.py.  python tests/test_handmedowns.py"""
import os, re, sys
try:
    from lupa import lua51 as L
except ImportError:
    import lupa as L

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
base = open(os.path.join(ROOT, "tests", "test_familymailbox.py"), encoding="utf-8").read()
MOCK = re.search(r"MOCK = r'''(.*?)'''", base, re.S).group(1)

ITEMS = r'''
-- id -> { name, quality, ilvl, minLevel, equipLoc, classID, subclassID, bindType, stats }
ITEMDATA = {
  [2318] = { "Light Leather", 1, 10, 0, "", 7, 6, 0 },
  [2589] = { "Linen Cloth", 1, 5, 0, "", 7, 5, 0 },
  [2770] = { "Copper Ore", 1, 10, 0, "", 7, 7, 0 },
  [2447] = { "Peacebloom", 1, 5, 0, "", 7, 9, 0 },
  [2678] = { "Mild Spices", 1, 5, 0, "", 7, 8, 0 },          -- cooking: never suggested
  [101] = { "Rugged Leather Vest", 2, 20, 15, "INVTYPE_CHEST", 4, 2, 2, { ITEM_MOD_AGILITY_SHORT = 3 } },
  [102] = { "Plate Helm", 2, 50, 45, "INVTYPE_HEAD", 4, 4, 2 },
  [103] = { "Apprentice Robe", 2, 22, 17, "INVTYPE_ROBE", 4, 1, 2, { ITEM_MOD_INTELLECT_SHORT = 4 } },
  [104] = { "Bound Blade", 3, 30, 15, "INVTYPE_WEAPON", 2, 7, 1 },
  [105] = { "Chain Hauberk", 2, 21, 16, "INVTYPE_CHEST", 4, 3, 2, { ITEM_MOD_STRENGTH_SHORT = 3 } },
  [106] = { "Brawler's Sword", 2, 25, 18, "INVTYPE_WEAPON", 2, 7, 2, { ITEM_MOD_STRENGTH_SHORT = 2 } },
  [107] = { "Grey Junk Ring", 0, 30, 10, "INVTYPE_FINGER", 4, 0, 2 },
  [108] = { "Silver Ring", 2, 18, 12, "INVTYPE_FINGER", 4, 0, 2 },
  [109] = { "Intellect Plate", 2, 40, 10, "INVTYPE_CHEST", 4, 3, 2, { ITEM_MOD_INTELLECT_SHORT = 5 } },
  [110] = { "Soulbound Gloves", 2, 25, 10, "INVTYPE_HAND", 4, 3, 1 },
  [201] = { "Worn Mail Vest", 1, 10, 5, "INVTYPE_CHEST", 4, 3, 1 },
  [202] = { "Frayed Robe", 1, 12, 5, "INVTYPE_ROBE", 4, 1, 1 },
  [203] = { "Copper Ring", 1, 20, 5, "INVTYPE_FINGER", 4, 0, 1 },
  [204] = { "Iron Ring", 1, 15, 5, "INVTYPE_FINGER", 4, 0, 1 },
}
for id, d in pairs(ITEMDATA) do LINKS[id] = "|cff1eff00|Hitem:" .. id .. "::::|h[" .. d[1] .. "]|h|r" end
UNCACHED = {}
C_Item.GetItemInfo = function(id)
  local d = ITEMDATA[id]
  if not d or UNCACHED[id] then return LINKS[id] and LINKS[id]:match("%[(.-)%]") and nil end
  return d[1], LINKS[id], d[2], d[3], d[4], "", "", 1, d[5], 0, 0, d[6], d[7], d[8]
end
C_Item.GetItemInfoInstant = function(id) local d = ITEMDATA[id]; if d then return id, "", "", d[5], 0, d[6], d[7] end end
C_Item.GetItemStats = function(link) local id = tonumber(link:match("item:(%d+)")); return ITEMDATA[id] and ITEMDATA[id][9] or {} end
C_Item.RequestLoadItemDataByID = function(id) REQUESTED = id end
PROFS = { { "Tailoring", 50, 150, 197 } }
function GetProfessions() if #PROFS == 0 then return nil end return 1, PROFS[2] and 2 or nil end
function GetProfessionInfo(i) local p = PROFS[i]; return p[1], 0, p[2], p[3], 0, 0, p[4] end
'''

passed = failed = 0
def check(name, cond):
    global passed, failed
    if cond: passed += 1
    else:
        failed += 1
        print("FAIL:", name)

lua = L.LuaRuntime(unpack_returned_tuples=True)
lua.execute(MOCK)
lua.execute(ITEMS)
for f in ("FamilyMailbox.lua", "FamilyMailbox_HandMeDown.lua", "FamilyMailbox_UI.lua"):
    lua.execute("local f = assert(loadstring(...)); f('FamilyMailbox')", open(os.path.join(ROOT, f), encoding="utf-8").read())
ev = lua.eval("function(e, ...) FamilyMailbox.frame:GetScript('OnEvent')(FamilyMailbox.frame, e, ...) end")
run, E = lua.execute, lua.eval

# Dad (warrior 60, the holder) logs in with a bag full of things
run("""
put(0, 1, 2318, 20); put(0, 2, 2589, 20); put(0, 3, 101, 1); put(0, 4, 102, 1); put(0, 5, 103, 1)
put(0, 6, 104, 1, true); put(0, 7, 105, 1); put(0, 8, 106, 1); put(0, 9, 107, 1); put(0, 10, 108, 1)
put(0, 11, 109, 1); put(0, 12, 2678, 10); put(0, 13, 2770, 5); put(0, 14, 2447, 8)
""")
ev("PLAYER_LOGIN")
check("professions recorded at login", E("FamilyMailboxDB.chars['Dad-MirageRaceway'].profs[1].line") == 197)
check("soulbound in bags remembered", E("FamilyMailboxDB.chars['Dad-MirageRaceway'].bagsBound[104]") is True)
check("BoE not marked bound", E("FamilyMailboxDB.chars['Dad-MirageRaceway'].bagsBound[101]") is None)

# the rest of the family, as Family Mailbox would have recorded them
run("""
local function char(name, class, level, profs, equipped, faction)
  FamilyMailboxDB.chars[name .. "-MirageRaceway"] = { name = name, full = name, realm = "Mirage Raceway", class = class,
    level = level, profs = profs, faction = faction or "Alliance",
    bags = {}, bank = {}, mail = {}, equipped = equipped or {} }
end
char("Aldric", "PALADIN", 18, { { name = "Leatherworking", rank = 75, max = 150, line = 165 }, { name = "Mining", rank = 60, max = 150, line = 186 } }, { [201] = 1 })
char("Tahu", "MAGE", 20, { { name = "Enchanting", rank = 40, max = 75, line = 333 } }, { [202] = 1, [203] = 1, [204] = 1 })
char("Bokor", "ROGUE", 14, nil, {})
char("Hordie", "WARRIOR", 50, { { name = "Leatherworking", rank = 1, max = 75, line = 165 } }, {}, "Horde")
""")
run("PROFS = {}; FamilyMailboxDB.chars['Dad-MirageRaceway'].profs = {}")

def hands(recipient=None, holder=None):
    lst = E("FamilyMailbox.HandMeDowns(%s, %s)" % (repr(recipient) if recipient else "nil", repr(holder) if holder else "nil"))
    return [dict(id=s.id, to=s.recipient.split("-")[0], kind=s.kind, text=s.text, frm=s.holder.split("-")[0]) for s in lst.values()]
def has(lst, id, to, kind=None):
    return any(s["id"] == id and s["to"] == to and (kind is None or s["kind"] == kind) for s in lst)

H = hands()
# --- the user's example: Dad has leather, Aldric is a leatherworker
check("leather -> the leatherworker", has(H, 2318, "Aldric", "mat"))
check("...says which profession and skill", any(s["id"] == 2318 and s["to"] == "Aldric" and "Leatherworking (75/150)" in s["text"] for s in H))
check("leather not to someone without Leatherworking", not has(H, 2318, "Tahu") and not has(H, 2318, "Bokor"))
check("cloth: nobody tailors, nobody gets it", not any(s["id"] == 2589 for s in H))
check("ore not to a miner (gathering doesn't count)", not has(H, 2770, "Aldric"))
check("herbs: no alchemist, no suggestion", not any(s["id"] == 2447 for s in H))
check("cooking spices never suggested", not any(s["id"] == 2678 for s in H))
check("other faction ignored", not any(s["to"] == "Hordie" for s in H))

# --- gear
check("a chest upgrade for the paladin (worn one is 10)", has(H, 105, "Aldric", "gear") or has(H, 109, "Aldric", "gear"))
check("leather vest not for a paladin", not has(H, 101, "Aldric"))
check("robe -> mage, item level vs worn", any(s["id"] == 103 and s["to"] == "Tahu" and "22 vs 12" in s["text"] for s in H))
check("leather vest -> rogue, ready at 15", any(s["id"] == 101 and s["to"] == "Bokor" and "ready at level 15" in s["text"] for s in H))
check("too high level: plate helm for nobody", not any(s["id"] == 102 for s in H))
check("soulbound item never suggested", not any(s["id"] == 104 for s in H))
check("grey junk never suggested", not any(s["id"] == 107 for s in H))
check("wrong stats: Strength sword not for the mage", not has(H, 106, "Tahu"))
check("sword -> paladin main hand (empty)", any(s["id"] == 106 and s["to"] == "Aldric" and "nothing worn" in s["text"] for s in H))
check("ring vs the worse of two worn rings (15)", any(s["id"] == 108 and s["to"] == "Tahu" and "18 vs 15" in s["text"] for s in H))
check("one suggestion per slot: best chest for Aldric only", len([s for s in H if s["to"] == "Aldric" and s["kind"] == "gear" and "Chest" in s["text"]]) == 1)
check("Intellect plate(mail) beats Chain Hauberk for the paladin chest", has(H, 109, "Aldric", "gear") and not has(H, 105, "Aldric", "gear"))
check("nothing for the holder themselves", not any(s["to"] == "Dad" for s in H))
check("gear listed before materials", [s["kind"] for s in H if s["to"] == "Aldric"][0] == "gear")

# --- the holder uses it themselves: keep it
run("FamilyMailboxDB.chars['Dad-MirageRaceway'].profs = { { name = 'Leatherworking', rank = 100, max = 150, line = 165 } }")
check("holder is a leatherworker too: leather stays", not has(hands(), 2318, "Aldric"))
run("FamilyMailboxDB.chars['Dad-MirageRaceway'].profs = {}")

# --- enchanting dust / elemental / Syndicator data without bound info
run("ITEMDATA[300] = { 'Strange Dust', 1, 10, 0, '', 7, 12, 0 }; LINKS[300] = '|Hitem:300::::|h[Strange Dust]|h'")
run("FamilyMailboxDB.chars['Dad-MirageRaceway'].bank = { [300] = 6, [110] = 1 }")
H = hands()
check("dust in the bank -> the enchanter", any(s["id"] == 300 and s["to"] == "Tahu" and "bank" == s.get("loc", "bank") for s in H))
check("bound gloves from a place with no bound record (bind on pickup) skipped", not any(s["id"] == 110 for s in H))

# --- filters
check("only for one recipient", all(s["to"] == "Tahu" for s in hands("Tahu-MirageRaceway")))
check("only from one holder", all(s["frm"] == "Dad" for s in hands(None, "Dad-MirageRaceway")))

# --- items not in the cache yet
run("UNCACHED[105] = true; FamilyMailbox.HandInfo_reset = true")
run("ITEMDATA[400] = { 'New Thing', 2, 60, 10, 'INVTYPE_CHEST', 4, 3, 2 }; LINKS[400] = '|Hitem:400::::|h[New Thing]|h'; UNCACHED[400] = true")
run("FamilyMailboxDB.chars['Dad-MirageRaceway'].bags[400] = 1")
check("uncached item: asked for, not suggested yet", not has(hands(), 400, "Aldric") and E("REQUESTED") == 400)
run("UNCACHED[400] = nil"); ev("GET_ITEM_INFO_RECEIVED", 400)
check("arrives later: refresh queued", E("#timers") >= 1)
check("arrived: now suggested", has(hands(), 400, "Aldric", "gear"))

# --- the window
run("FamilyMailbox.UI.ShowHand()")
check("hand tab opens", E("FamilyMailbox.UI.State().mode") == "hand" and E("FamilyMailboxFrame:IsShown()"))
res = E("FamilyMailbox.UI.Results()")
check("rows shown", len(list(res.values())) > 3)
row = E("FamilyMailboxFrame.rows[1]")
check("row names the recipient", "->" in row.name.text)
check("row says where it is and why", "from Dad's bags" in row.where.text)
first = res[1]
run("FamilyMailboxFrame.rows[1].scripts.OnClick(FamilyMailboxFrame.rows[1], 'LeftButton')")
check("click puts it on the post list for that character", E("FamilyMailbox.IsQueued('%s', %d)" % (first.recipient, first.id)))
check("row shows it's on the list", "on the post list" in E("FamilyMailboxFrame.rows[1].name.text"))
run("FamilyMailboxFrame.rows[1].scripts.OnClick(FamilyMailboxFrame.rows[1], 'LeftButton')")
check("click again takes it off", not E("FamilyMailbox.IsQueued('%s', %d)" % (first.recipient, first.id)))
check("Post all button shown", E("FamilyMailboxFrame.handAll.shown"))
run("FamilyMailbox.UI.PostAllHand()")
check("Post all queues everything shown", all(E("FamilyMailbox.IsQueued('%s', %d)" % (s.recipient, s.id)) for s in res.values()))
check("To post tab counts them", "(" in E("FamilyMailboxFrame.queueTab.text"))
run("FamilyMailbox.UI.State().selected = 'Tahu-MirageRaceway'; FamilyMailbox.UI.Refresh()")
check("picking a character on the left shows just theirs", all(s.recipient == "Tahu-MirageRaceway" for s in E("FamilyMailbox.UI.Results()").values()))
run("FamilyMailbox.UI.State().selected = nil")
run("FamilyMailboxFrame:Hide(); SlashCmdList.FAMILYMAILBOX('hand')")
check("/fm hand opens it", E("FamilyMailbox.UI.State().mode") == "hand" and E("FamilyMailboxFrame:IsShown()"))

# --- posting the queued hand-me-downs at the mailbox attaches them from the holder's bags
run("SEND = {}"); n = E("FamilyMailbox.PrepareMail('Aldric-MirageRaceway')")
check("at the mailbox: Aldric's hand-me-downs get attached", n[0] >= 1)

# --- login note
run("printed = {}; FamilyMailbox.HandLoginNote()")
check("login note on the holder", any("hand-me-down" in str(p) and "/fm hand" in str(p) for p in E("printed").values()))
run("printed = {}; FamilyMailboxDB.settings.handNote = false; FamilyMailbox.HandLoginNote()")
check("login note can be turned off", len(list(E("printed").values())) == 0)

print(f"{passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
