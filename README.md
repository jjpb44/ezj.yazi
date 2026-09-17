# ezj.yazi (ez jump)

Fork of [mikavilpas/easyjump.yazi](https://github.com/mikavilpas/easyjump.yazi)
(itself a fork of [DreamMaoMao/EasyJump.yazi](https://github.com/DreamMaoMao/EasyJump.yazi))
with these changes:

- **Hints render in the line-number gutter** (drawn by
  [relative-motions](https://github.com/dedukun/relative-motions)) instead of
  before the filename — the file list never shifts.
- **`q` cancels** an active jump (like `Esc`/`z`); `q` is removed from the hint
  keys so the trigger key always quits.
- **Colors are plain setup opts**, and while active the mode badge becomes
  `N+⚡` / `S+⚡` — the zap is a text-presentation glyph, so it follows your
  theme colors instead of rendering as emoji.

## Install

```sh
ya pkg add jjpb44/ezj
```

## Setup

```lua
-- ~/.config/yazi/init.lua
require("ezj"):setup({
	icon_fg = "#3AA99F",      -- label color (flexoki cyan here)
	first_key_fg = "#DA702C", -- first-key highlight while the chord is open
	dim_fg      = "#403E3C", -- unreachable hints dimmed while the chord is open
})
```

```toml
# ~/.config/yazi/keymap.toml
[[mgr.prepend_keymap]]
on = "q"
run = "plugin ezj"
desc = "Jump to file (EZJ)"
```

Gutter placement requires relative-motions line numbers to be active; without
them hints still render, but filenames may shift. Upstream repos carry no
LICENSE file — this fork keeps the same code provenance and credits the
original authors.

## Behavior

- The hovered entry keeps its motion number instead of a hint (opt back in with `hint_hovered = true`), rendered grayed-out so only the letter hints read as jump targets.
- **Chord labels**: every hint is a two-key chord over the first/second key sets (default `w e a s d` × `w e a s d` → `ww we wa ws wd ew …`). After the first key, matching hints highlight and unreachable ones dim.
- **Labels are packed**: the hovered row's hint moves to the next row, so no label from the pool is wasted — the last visible row simply goes unlabeled.
- While EZJ is waiting for a hint, `j`/`k` move the cursor like normal — they are never consumed as hints.
