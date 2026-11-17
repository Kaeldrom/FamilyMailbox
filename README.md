# Family Mailbox

A World of Warcraft addon for accounts shared by a family, or for anyone with alts. It remembers what every character is carrying and helps you post things between them.

- **One window for everyone** (`/fm`): pick a character, or "Everyone", then search. Use All / Bags / Bank / Mail / Worn to look in one place. Each item shows who has it and where: bags, bank, mail or worn.
- **Tooltips**: hover any item to see "Family has 23" and which characters hold it.
- **Gold**: each character's gold, plus the family total, including gold waiting in the mailbox.
- **Post queue**: right-click an item and tick who it's for. At a mailbox, the **Send to family** panel addresses the letter and attaches everything queued for that character in one click. You still press Send yourself.
- **Mail in transit**: items you post to a family character show up in their mail right away, before they log in.
- **Hand-me-downs** (`/fm hand`): gear and profession materials one character could pass to another (see below).

## Install

1. Download the zip (or **Code → Download ZIP** on GitHub) and extract it.
2. Rename the folder to `FamilyMailbox` if it's called `FamilyMailbox-main`.
3. Put it in `World of Warcraft\_forever_\Interface\AddOns\` so you have `AddOns\FamilyMailbox\FamilyMailbox.toc`.

Log in once on each character, and open the bank and mailbox once, so Family Mailbox can record them.

## Commands

| Command | What it does |
|---|---|
| `/fm` | Open or close the window |
| `/fm hand` | Hand-me-downs |
| `/fm tooltip` | Family counts on tooltips on/off |
| `/fm mailpanel` | The mailbox panel on/off |
| `/fm forget Name` | Forget a deleted or transferred character |

## Notes

- Items are grouped by item ID, so different random suffixes ("of the Bear") count together.
- Soulbound items can't be posted. They're skipped and you're told about them.
- Data is saved per account in `FamilyMailboxDB` and never leaves your computer.

## Tests

`pip install lupa`, then run `python tests/test_familymailbox.py` and `python tests/test_handmedowns.py`. This runs the addon against a mock WoW API in real Lua 5.1.

## Using Syndicator's data

If you also use Baganator or Syndicator, Family Mailbox imports what they've already recorded, so every character and bank shows up straight away.

## Why is a character's mail empty?

The game only lets addons read a mailbox while you're standing at an open one. Open a mailbox once on each character, and Family Mailbox remembers what's inside from then on. Until then, the character list still shows **mail waiting** when there's unread mail. Anything you post from one family character to another shows up straight away.

## Hand-me-downs

The **Hand-me-downs** tab (or `/fm hand`) lists what your characters could pass to each other:

- **Gear**: not soulbound, the right kind for the other character's class and level, with stats that suit them, and better than what they're wearing (item level), or ready within a few levels.
- **Materials** for their main professions: Gromir has Light Leather and Aldric is a leatherworker, so it's suggested for Aldric. Cooking, Fishing, First Aid and gathering professions aren't counted, and nothing is suggested if the holder uses it themselves.

Click a suggestion (or **Post all**) to add it to the post list, then post it from whoever has it at a mailbox. Professions are learnt when each character logs in, so log in on each once.
