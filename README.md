# Family Mailbox

A World of Warcraft addon for accounts shared by a family, or for anyone with alts. It remembers what every character is carrying and helps you post things between them.

- **One window for everyone** (`/fm`): pick a character, or "Everyone", then search. Each item shows who has it and where: bags, bank, mail or worn.
- **Tooltips**: hover any item to see "Family has 23" and which characters hold it.
- **Gold**: each character's gold, plus the family total, including gold waiting in the mailbox.
- **Post queue**: right-click an item and tick who it's for. At a mailbox, the **Send to family** panel addresses the letter and attaches everything queued for that character in one click. You still press Send yourself.
- **Mail in transit**: items you post to a family character show up in their mail right away, before they log in.

## Install

1. Download the zip (or **Code → Download ZIP** on GitHub) and extract it.
2. Rename the folder to `FamilyMailbox` if it's called `FamilyMailbox-main`.
3. Put it in `World of Warcraft\_forever_\Interface\AddOns\` so you have `AddOns\FamilyMailbox\FamilyMailbox.toc`.

Log in once on each character, and open the bank and mailbox once, so Family Mailbox can record them.

## Commands

| Command | What it does |
|---|---|
| `/fm` | Open or close the window |
| `/fm tooltip` | Family counts on tooltips on/off |
| `/fm mailpanel` | The mailbox panel on/off |
| `/fm forget Name` | Forget a deleted or transferred character |

## Notes

- Items are grouped by item ID, so different random suffixes ("of the Bear") count together.
- Soulbound items can't be posted. They're skipped and you're told about them.
- Data is saved per account in `FamilyMailboxDB` and never leaves your computer.

## Tests

`pip install lupa`, then run `python tests/test_familymailbox.py`. This runs the addon against a mock WoW API in real Lua 5.1.
