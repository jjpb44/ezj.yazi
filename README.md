# easyjump-gutter.yazi

Fork of [mikavilpas/easyjump.yazi](https://github.com/mikavilpas/easyjump.yazi)
(itself a fork of [DreamMaoMao/EasyJump.yazi](https://github.com/DreamMaoMao/EasyJump.yazi))
with three changes:

- **Hints render in the line-number gutter** (drawn by
  [relative-motions](https://github.com/dedukun/relative-motions)) instead of
  before the filename — the file list never shifts.
- **`q` cancels** an active jump (like `Esc`/`z`); `q` is removed from the hint
  keys so the trigger key always quits.
- **Colors are plain setup opts** and the status badge is a theme-styled bunny.

## Install

```sh
ya pkg add jjpb44/easyjump-gutter.yazi:easyjump-gutter
```

## Setup

```lua
-- ~/.config/yazi/init.lua
require("easyjump-gutter"):setup({
	icon_fg = "#3AA99F",      -- label color (flexoki cyan here)
	first_key_fg = "#DA702C", -- first-key highlight in double-label mode
})
```

```toml
# ~/.config/yazi/keymap.toml
[[mgr.prepend_keymap]]
on = "q"
run = "plugin easyjump-gutter"
desc = "Jump to file"
```

Gutter placement requires relative-motions line numbers to be active; without
them hints still render, but filenames may shift. Upstream repos carry no
LICENSE file — this fork keeps the same code provenance and credits the
original authors.
