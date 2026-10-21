## What this changes

## How I tested it

- [ ] `busted`, `luacheck .`, `luac5.4 -p` and `stylua --check main.lua src spec` pass
- [ ] Tried in the game with `prl runeui` (add a screenshot for anything visible)

## Checklist

- [ ] Shows only information the player can already see, and never acts for them
- [ ] No meaning carried by colour alone
- [ ] A tick where nothing changed still makes no component writes
